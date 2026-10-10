"""Shared logic for the SQL Dojo CLI and TUI. Standard library only (Python 3.8+)."""
from __future__ import annotations

import csv
import datetime as dt
import decimal
import hashlib
import io
import json
import os
import re
import shlex
import subprocess
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parent.parent
QUESTIONS_DIR = ROOT / "questions"
ANSWERS_DIR = ROOT / "answers"
PROGRESS_FILE = ANSWERS_DIR / "progress.json"
CACHE_DIR = ROOT / ".dojo-cache"
GENERATOR = ROOT / "db" / "generate.sql"
COMPOSE = ["docker", "compose", "-f", str(ROOT / "docker-compose.yml")]

LEVELS = {
    1: "Foundations",
    2: "Window functions",
    3: "Analytics patterns",
    4: "Advanced SQL",
    5: "Performance",
    6: "Production Postgres",
    7: "Modeling & ELT",
    8: "Lake & columnar",
    9: "Events & concurrency",
}
# kind of question:
#   query   one SELECT, graded by comparing its result with the reference
#   script  a migration-style script, run as a restricted role inside a transaction that is
#           rolled back; check.sql then inspects the state it produced
#   state   you change the database yourself (any statements, any way you like);
#           check.sql inspects the result
#   pipeline  your answer is a load script; the checker replays a plan such as
#           "setup, batch_1, answer, answer, batch_2, answer, answer, check" (new data lands
#           between runs, every run happens twice to prove it's idempotent), then check.sql
KINDS = ("query", "script", "state", "pipeline")
DATASET_TABLES = ["users", "categories", "products", "product_prices", "orders",
                  "order_items", "events", "reviews", "subscriptions"]
NULL = "<NULL>"
APP_NAME = "sql-dojo"
DEFAULT_TIMEOUT_S = 300


class DojoError(Exception):
    """Something the user should be told about (no traceback)."""


class QueryError(DojoError):
    """A query failed: syntax error, timeout, missing table, ..."""


class NeedsDuckDB(Exception):
    """Raised when a Level 8 (DuckDB) feature is used and the duckdb package isn't installed.
    The ./dojo launcher catches it, installs duckdb into .venv and retries."""


# --------------------------------------------------------------------------- #
# Questions
# --------------------------------------------------------------------------- #
class Question:
    def __init__(self, path: Path):
        self.dir = path
        meta, body = _parse_front_matter((path / "question.md").read_text(encoding="utf-8"))
        self.id = int(meta["id"])
        self.title = meta["title"]
        self.level = int(meta["level"])
        self.topics = _split_list(meta.get("topics", ""))
        self.tables = _split_list(meta.get("tables", ""))
        self.ordered = meta.get("ordered", "false").lower() == "true"
        self.decimals = int(meta.get("decimals", "2"))
        self.target_ms = float(meta["target_ms"]) if "target_ms" in meta else None
        self.target_scaling = meta.get("target_scaling", "constant")
        self.prompt, self.hints = _split_hints(body)
        self.kind = meta.get("kind", "query")
        self.engine = meta.get("engine", "postgres")  # postgres | duckdb
        # duckdb questions: an int, or "glob:<pattern>" = at most as many files as match
        self.max_files_read = meta.get("max_files_read") or None
        # duckdb labs: files/folders under lake/ that the lab owns (deleted when it resets)
        self.lake_paths = _split_list(meta.get("lake_paths", ""))
        # duckdb labs: after setup, stamp these files with a fixed old mtime (2026-01-01), so a
        # check can tell whether the learner rewrote them
        self.freeze_mtimes = _split_list(meta.get("freeze_mtimes", ""))
        if self.kind not in KINDS:
            raise ValueError(f"{path.name}: unknown kind {self.kind!r}")
        self.run_as = meta.get("run_as") or None
        self.setup_path = path / "setup.sql" if (path / "setup.sql").exists() else None
        self.plan = _split_list(meta.get("plan", "setup, answer, answer, check")) if self.kind == "pipeline" else []
        # data/workload steps; "parallel:worker*4" runs worker.sql in 4 concurrent sessions
        self.steps = list(dict.fromkeys(parallel_step(st)[0] if st.startswith("parallel:") else st
                                        for st in self.plan if st not in ("setup", "answer", "check")))
        for st in self.steps:
            if not (path / f"{st}.sql").exists():
                raise ValueError(f"{path.name}: plan step {st!r} has no {st}.sql")
        if self.plan and (self.plan[-1] != "check" or "answer" not in self.plan):
            raise ValueError(f"{path.name}: a pipeline plan needs at least one 'answer' and must end with 'check'")
        self.check_path = path / "check.sql"
        self.solution_path = path / "solution.sql"
        # Performance questions grade against the original (slow but correct) query.
        expected = path / "expected.sql"
        self.expected_path = expected if expected.exists() else self.solution_path

    @property
    def code(self) -> str:
        return f"{self.id:03d}"

    @property
    def answer_path(self) -> Path:
        return ANSWERS_DIR / f"{self.code}.sql"

    @property
    def level_name(self) -> str:
        return LEVELS.get(self.level, f"Level {self.level}")

    @property
    def is_perf(self) -> bool:
        return self.target_ms is not None

    @property
    def is_lab(self) -> bool:
        return self.kind != "query"

    def target_for_scale(self, scale: float) -> Optional[float]:
        if self.target_ms is None:
            return None
        if self.target_scaling == "linear":
            return self.target_ms * max(1.0, scale)
        return self.target_ms

    def target_label(self) -> str:
        if self.target_ms is None:
            return ""
        per = " × scale" if self.target_scaling == "linear" else ""
        return f"{self.target_ms:g} ms{per}"

    def markdown(self, heading: bool = True) -> str:
        """The question as Markdown (used by the TUI and the daily GitHub issue)."""
        out = []
        if heading:
            out.append(f"# Q{self.code} · {self.title}\n")
        out.append(f"**Level {self.level} · {self.level_name}** · {', '.join(self.topics)}  ")
        if self.tables:
            label = "Files" if self.engine == "duckdb" else "Tables"
            out.append(f"{label}: " + ", ".join(f"`{t}`" for t in self.tables) + "  ")
        if self.engine == "duckdb":
            out.append("🦆 **Runs in DuckDB** over the files in `lake/` (not in Postgres)  ")
        if self.is_perf:
            out.append(f"⏱ **Performance target: {self.target_label()}**")
        if self.kind == "script":
            out.append(f"🧪 **Lab:** write a script. It runs as role `{self.run_as}` in a transaction "
                       "that is rolled back after checking.")
        elif self.kind == "state":
            out.append("🧪 **Lab:** change the database however you like (the editor runs any statements), "
                       "then check.")
        elif self.kind == "pipeline":
            out.append("🧪 **Pipeline lab:** your answer is a script. Checking replays: "
                       + " → ".join("**your script**" if st == "answer" else f"`{step_label(st)}`"
                                    for st in self.plan))
        out.append("")
        out.append(self.prompt)
        return "\n".join(out)


def parallel_step(token: str) -> Tuple[str, int]:
    """'parallel:worker*4' -> ('worker', 4)"""
    name, _, n = token[len("parallel:"):].partition("*")
    return name.strip(), int(n or 2)


def step_label(step: str) -> str:
    """How a plan step reads in the UI: 'parallel:worker*4' -> 'worker ×4 at once'."""
    if step == "answer":
        return "your script"
    if step.startswith("parallel:"):
        name, n = parallel_step(step)
        return f"{name} ×{n} at once"
    return step


def _split_list(s: str) -> List[str]:
    return [x.strip() for x in s.split(",") if x.strip()]


def _parse_front_matter(text: str):
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        raise ValueError("question.md must start with a '---' front matter block")
    meta = {}
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            return meta, "\n".join(lines[i + 1:]).strip()
        if line.strip():
            key, _, value = line.partition(":")
            meta[key.strip()] = value.strip()
    raise ValueError("unterminated front matter")


def _split_hints(body: str):
    parts = re.split(r"^## Hints\s*$", body, maxsplit=1, flags=re.M)
    prompt = parts[0].strip()
    hints: List[str] = []
    if len(parts) > 1:
        for line in parts[1].splitlines():
            if line.startswith("- "):
                hints.append(line[2:].strip())
            elif line.startswith("  ") and hints:
                hints[-1] += " " + line.strip()
    return prompt, hints


def load_questions() -> List[Question]:
    qs = [Question(d) for d in sorted(QUESTIONS_DIR.iterdir()) if (d / "question.md").exists()]
    ids = [q.id for q in qs]
    if len(ids) != len(set(ids)):
        raise DojoError("duplicate question ids in questions/")
    return sorted(qs, key=lambda q: q.id)


def get_question(ref) -> Question:
    try:
        qid = int(ref)
    except (TypeError, ValueError):
        raise DojoError(f"'{ref}' is not a question number")
    for q in load_questions():
        if q.id == qid:
            return q
    raise DojoError(f"no question {qid}. See ./dojo list")


# --------------------------------------------------------------------------- #
# Progress: answers/progress.json is meant to be committed. It's your log.
# --------------------------------------------------------------------------- #
def load_progress() -> dict:
    if PROGRESS_FILE.exists():
        return json.loads(PROGRESS_FILE.read_text(encoding="utf-8"))
    return {}


def save_progress(progress: dict) -> None:
    ANSWERS_DIR.mkdir(exist_ok=True)
    PROGRESS_FILE.write_text(json.dumps(progress, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def update_progress(q: Question, fn: Callable[[dict], None]) -> dict:
    progress = load_progress()
    entry = progress.setdefault(q.code, {})
    fn(entry)
    save_progress(progress)
    return entry


def now_iso() -> str:
    return dt.datetime.now().replace(microsecond=0).isoformat()


def is_solved(progress: dict, q: Question) -> bool:
    return bool(progress.get(q.code, {}).get("solved_at"))


def next_question(exclude=()) -> Optional[Question]:
    """The lowest-numbered unsolved question."""
    progress = load_progress()
    for q in load_questions():
        if not is_solved(progress, q) and q.id not in exclude:
            return q
    return None


# Where you left off. A local file (gitignored): it changes every time you switch questions.
def _session_file() -> Path:
    return ANSWERS_DIR / ".session.json"


def remember_question(q: Question) -> None:
    ANSWERS_DIR.mkdir(exist_ok=True)
    _session_file().write_text(json.dumps({"last_question": q.id, "at": now_iso()}) + "\n", encoding="utf-8")


def last_question_id() -> Optional[int]:
    try:
        return int(json.loads(_session_file().read_text(encoding="utf-8"))["last_question"])
    except (OSError, ValueError, KeyError, TypeError):
        return None


def resume_question() -> Optional[Question]:
    """The question you were last on. If you finished it, the next unsolved one after it."""
    qs = load_questions()
    last = last_question_id()
    ids = [q.id for q in qs]
    if last not in ids:
        return next_question()
    progress = load_progress()
    i = ids.index(last)
    for q in qs[i:] + qs[:i]:
        if not is_solved(progress, q):
            return q
    return None


_STUB_HELP = {
    "query": "-- Write ONE query below. Check it with ./dojo check {id} (Ctrl+T in the TUI).",
    "script": "-- Write your script below (several statements are fine). It runs as role {run_as}\n"
              "-- inside a transaction that is rolled back. Check it with ./dojo check {id} (Ctrl+T).",
    "state": "-- Lab scratchpad. Ctrl+R (./dojo run {id}) runs everything here as the superuser,\n"
             "-- statement by statement, with autocommit. Then check the result with Ctrl+T.",
    "pipeline": "-- Your load script (any statements). Ctrl+R / ./dojo run {id} runs it against the lab as it\n"
                "-- is now; land data with the lab steps (Ctrl+P, or ./dojo lab-step {id} <step>).\n"
                "-- Ctrl+T / ./dojo check {id} replays the whole pipeline from scratch.",
}


def ensure_stub(q: Question) -> bool:
    """Create answers/NNN.sql if missing. Returns True if created."""
    if q.answer_path.exists():
        return False
    ANSWERS_DIR.mkdir(exist_ok=True)
    q.answer_path.write_text(
        f"-- Q{q.code} · {q.title}\n" + _STUB_HELP[q.kind].format(id=q.id, run_as=q.run_as) + "\n\n",
        encoding="utf-8")
    update_progress(q, lambda e: e.setdefault("started_at", now_iso()))
    return True


def reveal_hint(q: Question, all_hints: bool = False) -> List[str]:
    """Reveal one more hint (or all) and return every hint revealed so far."""
    def bump(e):
        used = e.get("hints", 0)
        e["hints"] = len(q.hints) if all_hints else min(len(q.hints), used + 1)
    entry = update_progress(q, bump)
    return q.hints[:entry["hints"]]


def revealed_hints(q: Question) -> List[str]:
    return q.hints[:load_progress().get(q.code, {}).get("hints", 0)]


def mark_solution_viewed(q: Question) -> None:
    if not is_solved(load_progress(), q):
        update_progress(q, lambda e: e.__setitem__("revealed", True))


# --------------------------------------------------------------------------- #
# SQL text handling
# --------------------------------------------------------------------------- #
def _skip_quoted(text: str, i: int) -> int:
    """Given text[i] is a quote char, return the index just past the closing quote."""
    ch, j, n = text[i], i + 1, len(text)
    while j < n:
        if text[j] == ch:
            if j + 1 < n and text[j + 1] == ch:
                j += 2
                continue
            return j + 1
        j += 1
    return n


def _dollar_tag(text: str, i: int) -> Optional[str]:
    m = re.match(r"\$([A-Za-z_][A-Za-z0-9_]*)?\$", text[i:])
    return m.group(0) if m else None


def strip_sql(sql: str) -> str:
    """Remove comments and trailing semicolons; refuse multiple statements."""
    text = _strip_comments(sql)
    while text.endswith(";"):
        text = text[:-1].rstrip()
    if _has_top_level_semicolon(text):
        raise QueryError("Your answer must be a single query (found more than one statement).\n"
                         "Run setup like CREATE INDEX in psql (./dojo psql), not in the answer file.")
    return text


def _strip_comments(sql: str) -> str:
    """A tiny lexer that understands '...', "...", $tag$...$tag$, -- and /* */."""
    out, i, n = [], 0, len(sql)
    while i < n:
        ch = sql[i]
        if sql.startswith("--", i):
            j = sql.find("\n", i)
            i = n if j == -1 else j
        elif sql.startswith("/*", i):
            depth, i = 1, i + 2
            while i < n and depth:
                if sql.startswith("/*", i):
                    depth, i = depth + 1, i + 2
                elif sql.startswith("*/", i):
                    depth, i = depth - 1, i + 2
                else:
                    i += 1
            out.append(" ")
        elif ch in ("'", '"'):
            j = _skip_quoted(sql, i)
            out.append(sql[i:j])
            i = j
        elif ch == "$" and _dollar_tag(sql, i):
            tag = _dollar_tag(sql, i)
            j = sql.find(tag, i + len(tag))
            j = n if j == -1 else j + len(tag)
            out.append(sql[i:j])
            i = j
        else:
            out.append(ch)
            i += 1
    return "".join(out).strip()


def split_statements(sql: str) -> List[str]:
    """Split a script into statements (comments removed)."""
    text = _strip_comments(sql)
    out, start, i, n = [], 0, 0, len(text)
    while i < n:
        ch = text[i]
        if ch in ("'", '"'):
            i = _skip_quoted(text, i)
        elif ch == "$" and _dollar_tag(text, i):
            tag = _dollar_tag(text, i)
            j = text.find(tag, i + len(tag))
            i = n if j == -1 else j + len(tag)
        elif ch == ";":
            out.append(text[start:i].strip())
            start = i = i + 1
        else:
            i += 1
    out.append(text[start:].strip())
    return [s for s in out if s]


_FORBIDDEN_IN_SCRIPT = re.compile(
    r"^(BEGIN|START|COMMIT|END|ABORT|ROLLBACK(?!\s+TO)|SET\s+(LOCAL\s+|SESSION\s+)?ROLE|RESET\s+(ROLE|ALL)"
    r"|SET\s+(LOCAL\s+|SESSION\s+)?SESSION\s+AUTHORIZATION|RESET\s+SESSION)\b", re.I)


def validate_script(sql: str) -> List[str]:
    """Statements of a script-lab answer, refusing ones that would escape the sandbox."""
    stmts = split_statements(sql)
    if not stmts:
        raise QueryError("no SQL found (the file only has comments)")
    if re.search(r"(^|\n)\s*\\", _strip_comments(sql)):
        raise QueryError("psql backslash commands aren't allowed in the script")
    for st in stmts:
        if _FORBIDDEN_IN_SCRIPT.match(st):
            raise QueryError(f"Not allowed in a lab script: {st.split()[0].upper()} ... "
                             "The checker runs your script inside its own transaction, as the lab's role.")
    return stmts


def _has_top_level_semicolon(text: str) -> bool:
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch in ("'", '"'):
            i = _skip_quoted(text, i)
        elif ch == "$" and _dollar_tag(text, i):
            tag = _dollar_tag(text, i)
            j = text.find(tag, i + len(tag))
            i = n if j == -1 else j + len(tag)
        elif ch == ";":
            return True
        else:
            i += 1
    return False


# --------------------------------------------------------------------------- #
# Talking to Postgres (through psql, so there are no Python dependencies)
# --------------------------------------------------------------------------- #
@dataclass
class Result:
    header: List[str]
    rows: List[List[str]]
    ms: float

    def to_json(self) -> dict:
        return {"header": self.header, "rows": self.rows, "ms": self.ms}

    @classmethod
    def from_json(cls, d: dict) -> "Result":
        return cls(d["header"], [list(r) for r in d["rows"]], d["ms"])


def using_custom_psql() -> bool:
    return bool(os.environ.get("DOJO_PSQL"))


def psql_cmd(interactive: bool = False) -> List[str]:
    custom = os.environ.get("DOJO_PSQL")
    if custom:
        return shlex.split(custom)
    cmd = COMPOSE + ["exec"]
    if not interactive:
        cmd.append("-T")
    return cmd + ["db", "psql", "-U", "dojo", "-d", "dojo"]


def psql(script: str, extra_args=(), timeout=None) -> subprocess.CompletedProcess:
    cmd = psql_cmd() + ["-X", "-q", "-v", "ON_ERROR_STOP=1", *extra_args, "-f", "-"]
    try:
        return subprocess.run(cmd, input=script, capture_output=True, text=True,
                              timeout=timeout, encoding="utf-8")
    except FileNotFoundError:
        raise DojoError(f"could not run {cmd[0]!r}. Is Docker installed? (or set DOJO_PSQL)")
    except subprocess.TimeoutExpired:
        raise QueryError("timed out")


_TIME_RE = re.compile(r"^Time: ([\d.]+) ms.*$", re.M)


def _clean_error(proc: subprocess.CompletedProcess) -> str:
    err = (proc.stderr or proc.stdout or "").strip()
    return re.sub(r"^psql:<stdin>:\d+: ", "", err, flags=re.M) or f"psql exited with code {proc.returncode}"


def run_query(sql: str, timeout_s: int = DEFAULT_TIMEOUT_S) -> Result:
    body = strip_sql(sql)
    if not body:
        raise QueryError("no SQL found (the file only has comments)")
    script = (f"SET application_name = '{APP_NAME}';\n"
              f"SET statement_timeout = '{timeout_s}s';\n"
              f"\\pset null '{NULL}'\n"
              f"\\timing on\n{body}\n;\n")
    proc = psql(script, extra_args=["--csv"], timeout=timeout_s + 30)
    if proc.returncode != 0:
        err = _clean_error(proc)
        if "statement timeout" in err:
            err += f"\n(the query ran for more than {timeout_s}s)"
        elif "canceling statement due to user request" in err:
            err = "Cancelled."
        raise QueryError(err)
    out = proc.stdout
    times = [float(t) for t in _TIME_RE.findall(out)]
    rows = list(csv.reader(io.StringIO(_TIME_RE.sub("", out).strip("\n"))))
    if not rows:
        raise QueryError("the statement returned no result set (is it a SELECT?)")
    return Result(rows[0], rows[1:], times[-1] if times else 0.0)


def explain(sql: str, analyze: bool = True, timeout_s: int = DEFAULT_TIMEOUT_S) -> str:
    body = strip_sql(sql)
    if not body:
        raise QueryError("no SQL found (the file only has comments)")
    opts = "ANALYZE, BUFFERS" if analyze else "COSTS"
    proc = psql(f"SET application_name = '{APP_NAME}';\n"
                f"SET statement_timeout = '{timeout_s}s';\n"
                f"EXPLAIN ({opts}) {body};\n", timeout=timeout_s + 30)
    if proc.returncode != 0:
        raise QueryError(_clean_error(proc))
    return proc.stdout.rstrip()


def run_script(sql: str, timeout_s: int = DEFAULT_TIMEOUT_S) -> str:
    """Run any statements (autocommit, as the superuser) and return psql's output as text."""
    if not split_statements(sql):
        raise QueryError("no SQL found (the file only has comments)")
    script = (f"SET application_name = '{APP_NAME}';\nSET statement_timeout = '{timeout_s}s';\n"
              f"\\set QUIET off\n\\timing on\n\\set ECHO queries\n{sql}\n")
    cmd = psql_cmd() + ["-X", "-q", "-v", "ON_ERROR_STOP=1", "-f", "-"]
    try:
        proc = subprocess.run(cmd, input=script, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, encoding="utf-8", timeout=timeout_s + 30)
    except FileNotFoundError:
        raise DojoError(f"could not run {cmd[0]!r}. Is Docker installed? (or set DOJO_PSQL)")
    except subprocess.TimeoutExpired:
        raise QueryError("timed out")
    out = re.sub(r"^Timing is on\.\n", "", proc.stdout, flags=re.M)
    out = re.sub(r"^psql:<stdin>:\d+: ", "", out, flags=re.M).rstrip()
    if proc.returncode != 0:
        raise QueryError(out or f"psql exited with code {proc.returncode}")
    return out


def cancel_queries() -> None:
    """Cancel any running dojo query (used by the TUI's Esc key)."""
    psql(f"SELECT pg_cancel_backend(pid) FROM pg_stat_activity "
         f"WHERE application_name = '{APP_NAME}' AND pid <> pg_backend_pid();", timeout=15)


def db_meta() -> Dict[str, str]:
    """{} when the database is down or not generated yet."""
    try:
        proc = psql("SELECT key, value FROM _dojo.meta;", extra_args=["--csv", "-t"], timeout=20)
    except DojoError:
        return {}
    if proc.returncode != 0:
        return {}
    return dict(r for r in csv.reader(io.StringIO(proc.stdout)) if len(r) == 2)


def require_db() -> Dict[str, str]:
    meta = db_meta()
    if not meta:
        raise DojoError("the database is not running or has no data yet. Run: ./dojo up")
    return meta


def query_rows(sql: str) -> List[List[str]]:
    proc = psql(sql, extra_args=["--csv", "-t"], timeout=60)
    if proc.returncode != 0:
        raise QueryError(_clean_error(proc))
    return [r for r in csv.reader(io.StringIO(proc.stdout)) if r]


def schema() -> List[Tuple[str, str, str]]:
    """(table, column, type) for the dataset tables plus anything you created in public."""
    return [tuple(r) for r in query_rows("""
        SELECT c.relname, a.attname, format_type(a.atttypid, a.atttypmod)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
        WHERE n.nspname = 'public' AND c.relkind IN ('r', 'm', 'v')
          AND c.relname NOT LIKE 'pg\\_stat\\_statements%'
        ORDER BY c.relname, a.attnum;""")]


def table_stats() -> List[Tuple[str, str, str]]:
    """(table, approx rows, size)."""
    return [tuple(r) for r in query_rows("""
        SELECT c.relname,
               CASE WHEN c.reltuples < 0 THEN '?' ELSE to_char(c.reltuples, 'FM999,999,999,990') END,
               pg_size_pretty(pg_total_relation_size(c.oid))
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind IN ('r', 'm')
        ORDER BY pg_total_relation_size(c.oid) DESC;""")]


# --------------------------------------------------------------------------- #
# Database lifecycle
# --------------------------------------------------------------------------- #
def docker_ok() -> bool:
    try:
        return subprocess.run(["docker", "info"], capture_output=True, timeout=20).returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def compose_up_cmd() -> List[str]:
    return COMPOSE + ["up", "-d", "--wait"]


def generate_cmd(scale: float) -> List[str]:
    return psql_cmd() + ["-X", "-q", "-v", "ON_ERROR_STOP=1", "-v", f"scale={scale:g}", "-f", "-"]


def stream(cmd: List[str], on_line: Callable[[str], None], stdin_path: Optional[Path] = None) -> int:
    """Run a command, feeding each output line to on_line. Returns the exit code."""
    stdin = open(stdin_path, "rb") if stdin_path else subprocess.DEVNULL
    try:
        proc = subprocess.Popen(cmd, stdin=stdin, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, encoding="utf-8", errors="replace")
    except FileNotFoundError:
        raise DojoError(f"could not run {cmd[0]!r}. Is Docker installed?")
    finally:
        if stdin_path:
            stdin.close()
    assert proc.stdout is not None
    for line in proc.stdout:
        on_line(line.rstrip("\n"))
    return proc.wait()


def start_database(on_line: Callable[[str], None]) -> None:
    if using_custom_psql():
        return
    if not docker_ok():
        raise DojoError("Docker is not running. Start Docker Desktop (or the docker daemon) and try again.")
    if stream(compose_up_cmd(), on_line) != 0:
        raise DojoError("docker compose up failed (see the output above)")


# Peak disk use while generating, measured: the finished dataset plus temporary sort files.
_GB = 1024 ** 3
_PEAK_GB_PER_SCALE = 1.1
_PEAK_GB_FIXED = 0.5


def disk_needed_bytes(scale: float) -> int:
    return int((_PEAK_GB_FIXED + _PEAK_GB_PER_SCALE * scale) * _GB)


def container_free_bytes() -> Optional[int]:
    """Free space on the disk holding the database (inside Docker's VM), or None if unknown."""
    if using_custom_psql():
        return None
    try:
        proc = subprocess.run(COMPOSE + ["exec", "-T", "db", "df", "-Pk", "/var/lib/postgresql/data"],
                              capture_output=True, text=True, timeout=30)
        return int(proc.stdout.strip().splitlines()[-1].split()[3]) * 1024 if proc.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired, IndexError, ValueError):
        return None


def _reclaimable_bytes() -> int:
    """Space the generator frees when it drops the current data."""
    try:
        rows = query_rows("SELECT coalesce(sum(pg_total_relation_size(c.oid)), 0) FROM pg_class c "
                          "JOIN pg_namespace n ON n.oid = c.relnamespace "
                          "WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND c.relkind IN ('r', 'm');")
        return int(rows[0][0])
    except (DojoError, IndexError, ValueError):
        return 0


def disk_problem(scale: float) -> Optional[str]:
    free = container_free_bytes()
    if free is None:
        return None
    need, have = disk_needed_bytes(scale), free + _reclaimable_bytes()
    if have >= need:
        return None
    return (f"Not enough disk space inside Docker for scale {scale:g}: generating needs about "
            f"{need / _GB:.0f} GB and only {have / _GB:.1f} GB is available.\n"
            "Docker Desktop keeps images, containers and volumes in a virtual disk with its own size "
            "limit, separate from your computer's free space. Raise it in Docker Desktop → Settings → "
            "Resources → Advanced (disk usage limit), free space with `docker system prune`, or pick a "
            "smaller scale. (./dojo generate --force tries anyway.)")


def generate_data(scale: float, on_line: Callable[[str], None], force: bool = False) -> None:
    if scale <= 0:
        raise DojoError("scale must be positive")
    problem = disk_problem(scale)
    if problem and not force:
        raise DojoError(problem)

    def clean(line: str) -> None:
        on_line(re.sub(r"^psql:<stdin>:\d+: ", "", line))
    if stream(generate_cmd(scale), clean, stdin_path=GENERATOR) != 0:
        raise DojoError("generation failed (see the output above)")


# --------------------------------------------------------------------------- #
# Grading
# --------------------------------------------------------------------------- #
_NUM_RE = re.compile(r"^-?(\d+(\.\d*)?|\.\d+)([eE][-+]?\d+)?$")


def normalize(value: str, decimals: int):
    if value == NULL:
        return None
    if _NUM_RE.match(value):
        d = decimal.Decimal(value).quantize(decimal.Decimal(1).scaleb(-decimals),
                                            rounding=decimal.ROUND_HALF_UP)
        if d == 0:
            d = abs(d)
        return format(d.normalize(), "f")
    return value


def fmt_row(row) -> str:
    return "(" + ", ".join("NULL" if v is None else v for v in row) + ")"


def compare(expected: Result, actual: Result, q: Question) -> Tuple[bool, List[Tuple[str, str]]]:
    """Compare result sets. Returns (ok, [(kind, message)]), kind in info|warn|error."""
    msgs: List[Tuple[str, str]] = []
    if len(expected.header) != len(actual.header):
        return False, [("error", f"Expected {len(expected.header)} columns ({', '.join(expected.header)}), "
                                 f"got {len(actual.header)} ({', '.join(actual.header)}).")]
    exp = [tuple(normalize(v, q.decimals) for v in r) for r in expected.rows]
    act = [tuple(normalize(v, q.decimals) for v in r) for r in actual.rows]
    if any(a != b for a, b in zip(expected.header, actual.header)):
        msgs.append(("info", f"Column names differ from the spec ({', '.join(expected.header)}). "
                             "That's fine: only values are checked."))
    if q.ordered and exp == act:
        return True, msgs
    if Counter(exp) == Counter(act):
        if not q.ordered:
            return True, msgs
        msgs.append(("error", "Exactly the right rows, but in the wrong order. "
                              "Check your ORDER BY, including tie-breakers."))
        return False, msgs
    if len(exp) != len(act):
        msgs.append(("error", f"Expected {len(exp)} rows, got {len(act)}."))
    missing = Counter(exp) - Counter(act)
    extra = Counter(act) - Counter(exp)
    if missing:
        msgs.append(("error", f"{sum(missing.values())} expected row(s) are missing, e.g.:"))
        msgs.extend(("row", fmt_row(r)) for r in list(missing.elements())[:5])
    if extra:
        msgs.append(("error", f"{sum(extra.values())} row(s) should not be there, e.g.:"))
        msgs.extend(("row", fmt_row(r)) for r in list(extra.elements())[:5])
    return False, msgs


def reference_result(q: Question, meta: dict, refresh: bool = False,
                     on_status: Optional[Callable[[str], None]] = None) -> Result:
    sql = q.expected_path.read_text(encoding="utf-8")
    stamp = (_lake().require_lake().get("built_at", "") if q.engine == "duckdb" else "")
    key = hashlib.sha256("|".join([sql, meta.get("scale", ""), meta.get("generated_at", ""), stamp])
                         .encode()).hexdigest()[:16]
    path = CACHE_DIR / f"{q.code}-{key}.json"
    if path.exists() and not refresh:
        return Result.from_json(json.loads(path.read_text(encoding="utf-8")))
    if on_status:
        on_status("Computing the reference answer (cached after the first run)...")
    try:
        res = answer_query(q, sql, timeout_s=3600)
    except QueryError as e:
        raise DojoError(f"the reference solution failed (please report this):\n{e}")
    CACHE_DIR.mkdir(exist_ok=True)
    for old in CACHE_DIR.glob(f"{q.code}-*.json"):
        old.unlink()
    path.write_text(json.dumps(res.to_json()), encoding="utf-8")
    return res


@dataclass
class Grade:
    correct: bool = False
    fast_enough: bool = True
    error: Optional[str] = None
    messages: List[Tuple[str, str]] = field(default_factory=list)
    expected: Optional[Result] = None
    actual: Optional[Result] = None
    best_ms: Optional[float] = None
    timings: List[float] = field(default_factory=list)
    target_ms: Optional[float] = None
    first_solve: bool = False
    attempts: int = 0
    hints: int = 0
    checks: List[Tuple[str, bool, str]] = field(default_factory=list)  # labs
    output: str = ""  # labs: what your script printed

    @property
    def passed(self) -> bool:
        return self.correct and self.fast_enough


def grade(q: Question, sql: str, timeout_s: int = DEFAULT_TIMEOUT_S,
          on_status: Optional[Callable[[str], None]] = None, record: bool = True) -> Grade:
    """Run the answer, compare with the reference, update progress (unless record=False)."""
    meta = require_db()
    g = Grade(target_ms=q.target_for_scale(float(meta.get("scale", 1))))
    if q.is_lab and q.engine == "duckdb":
        try:
            _grade_duck_lab(q, g, on_status)
        except QueryError as e:
            g.error = str(e)
        if record:
            _record_attempt(q, g)
        return g
    if q.is_lab:
        try:
            _grade_lab(q, sql, g, timeout_s, on_status)
        except QueryError as e:
            g.error = str(e)
        if record:
            _record_attempt(q, g)
        return g
    if q.setup_path is not None and not lab_is_set_up(q):
        setup_lab(q)
    g.expected = reference_result(q, meta, on_status=on_status)
    runs = 3 if q.is_perf else 1
    try:
        for i in range(runs):
            if on_status:
                on_status("Running your query" + (f" ({i + 1}/{runs})" if runs > 1 else "") + "...")
            g.actual = answer_query(q, sql, timeout_s=timeout_s)
            g.timings.append(g.actual.ms)
            if i == 0:
                g.correct, g.messages = compare(g.expected, g.actual, q)
                if not g.correct or (g.target_ms and g.actual.ms > 5 * g.target_ms):
                    break  # wrong, or hopelessly slow: no point in re-running
        g.best_ms = min(g.timings)
        g.fast_enough = g.target_ms is None or g.best_ms <= g.target_ms
        if g.correct and q.engine == "duckdb" and q.max_files_read:
            limit = (_lake().count_files(q.max_files_read[5:]) if q.max_files_read.startswith("glob:")
                     else int(q.max_files_read))
            n = _lake().files_read(sql, timeout_s=timeout_s)
            if n > limit:
                g.correct = False
                g.messages.append(("error", f"Right answer, but your query read {n} files and should read at "
                                            f"most {limit}. Filter on the partition column so DuckDB can skip "
                                            "whole files (see EXPLAIN: \"Total Files Read\")."))
            else:
                g.messages.append(("info", f"Files read: {n} (limit {limit})."))
    except QueryError as e:
        g.error = str(e)
        g.correct = False
    if record:
        _record_attempt(q, g)
    return g


def _record_attempt(q: Question, g: Grade) -> None:
    def record(e: dict):
        e.setdefault("started_at", now_iso())
        e["attempts"] = e.get("attempts", 0) + 1
        if g.passed:
            if not e.get("solved_at"):
                e["solved_at"] = now_iso()
                g.first_solve = True
            if g.best_ms is not None:
                e["best_ms"] = round(min(g.best_ms, e.get("best_ms", g.best_ms)), 1)
        g.attempts, g.hints = e["attempts"], e.get("hints", 0)
    update_progress(q, record)


# --------------------------------------------------------------------------- #
# Engine dispatch (Postgres via psql, or DuckDB over ./lake for Level 8)
# --------------------------------------------------------------------------- #
def _lake():
    from . import lake
    return lake


def answer_query(q: Question, sql: str, timeout_s: int = DEFAULT_TIMEOUT_S) -> Result:
    return _lake().run_query(sql, timeout_s) if q.engine == "duckdb" else run_query(sql, timeout_s)


def answer_script(q: Question, sql: str, timeout_s: int = DEFAULT_TIMEOUT_S) -> str:
    return _lake().run_script(sql, timeout_s) if q.engine == "duckdb" else run_script(sql, timeout_s)


def answer_explain(q: Question, sql: str, analyze: bool = True, timeout_s: int = DEFAULT_TIMEOUT_S) -> str:
    if q.engine == "duckdb":
        return _lake().explain(sql, analyze, timeout_s)
    return explain(sql, analyze, timeout_s)


def cancel_all() -> None:
    try:
        cancel_queries()
    except DojoError:
        pass
    try:
        _lake().cancel()
    except Exception:
        pass


def engine_ready(q: Question) -> bool:
    """For DuckDB questions: is the lake built?"""
    return q.engine != "duckdb" or bool(_lake().status())


# --------------------------------------------------------------------------- #
# Labs
# --------------------------------------------------------------------------- #
_LABS_TABLE = "CREATE TABLE IF NOT EXISTS _dojo.labs (question_id int PRIMARY KEY, set_up_at timestamptz NOT NULL);"


def lab_is_set_up(q: Question) -> bool:
    if q.engine == "duckdb":
        return _lake().lab_is_set_up(q)
    if q.setup_path is None:
        return True
    try:
        rows = query_rows(f"{_LABS_TABLE}\nSELECT 1 FROM _dojo.labs WHERE question_id = {q.id};")
    except QueryError:
        return False
    return bool(rows)


def setup_lab(q: Question) -> None:
    """(Re)create the lab's objects. Idempotent; resets any work done in a state lab."""
    if q.engine == "duckdb":
        _lake().setup_lab(q)
        return
    if q.setup_path is None:
        return
    proc = psql(q.setup_path.read_text(encoding="utf-8") + f"\n{_LABS_TABLE}\n"
                f"INSERT INTO _dojo.labs VALUES ({q.id}, now()) "
                f"ON CONFLICT (question_id) DO UPDATE SET set_up_at = now();\n", timeout=600)
    if proc.returncode != 0:
        raise DojoError(f"setting up the lab failed:\n{_clean_error(proc)}")


def run_lab_step(q: Question, step: str) -> str:
    """Run one step of a pipeline lab (setup or a data step like batch_1). Returns psql output."""
    if step == "setup":
        setup_lab(q)
        return "Lab reset."
    if step not in q.steps:
        raise DojoError(f"Q{q.code} has no step {step!r}. Steps: setup, {', '.join(q.steps)}")
    parallel = [parallel_step(t) for t in q.plan if t.startswith("parallel:")]
    n = next((k for name, k in parallel if name == step), 0)
    if n:
        error = _run_parallel(q.dir / f"{step}.sql", n, DEFAULT_TIMEOUT_S)
        if error:
            raise QueryError(error)
        return f"Ran {step}.sql in {n} concurrent sessions."
    return run_script((q.dir / f"{step}.sql").read_text(encoding="utf-8"))


def _parse_checks(csv_text: str) -> List[Tuple[str, bool, str]]:
    csv.field_size_limit(max(csv.field_size_limit(), 16 * 1024 * 1024))
    rows = list(csv.reader(io.StringIO(csv_text.strip("\n"))))
    if not rows or [c.lower() for c in rows[0][:2]] != ["check", "ok"]:
        raise DojoError("check.sql must return columns (check, ok, detail)")
    def detail(r):
        d = r[2] if len(r) > 2 and r[2] != NULL else ""
        return d if len(d) <= 200 else d[:197] + "..."
    return [(r[0], r[1] == "t", detail(r)) for r in rows[1:]]


_MARK = "__DOJO_CHECK__"


def _grade_lab(q: Question, sql: str, g: "Grade", timeout_s: int,
               on_status: Optional[Callable[[str], None]]) -> None:
    check_sql = q.check_path.read_text(encoding="utf-8")
    if q.kind == "pipeline":
        _grade_pipeline(q, sql, check_sql, g, timeout_s, on_status)
        return
    if q.kind == "script":
        validate_script(sql)
        if on_status:
            on_status("Resetting the lab...")
        setup_lab(q)
        if on_status:
            on_status(f"Running your script as {q.run_as or 'the superuser'}, then checking...")
        script = (f"SET application_name = '{APP_NAME}';\nSET statement_timeout = '{timeout_s}s';\n"
                  "\\pset null '" + NULL + "'\nBEGIN;\n"
                  + (f"SET LOCAL ROLE {q.run_as};\n" if q.run_as else "")
                  + f"{sql}\n;\nRESET ROLE;\n\\echo {_MARK}\n\\pset format csv\n{check_sql}\n;\nROLLBACK;\n")
    else:
        if not lab_is_set_up(q):
            if on_status:
                on_status("Setting up the lab...")
            setup_lab(q)
            g.error = ("The lab wasn't set up yet, so it has just been created for you. "
                       "Do the task, then check again.")
            return
        if on_status:
            on_status("Checking the database state...")
        script = (f"SET application_name = '{APP_NAME}';\n\\pset null '{NULL}'\n"
                  f"\\echo {_MARK}\n\\pset format csv\n{check_sql}\n")
    proc = psql(script, timeout=timeout_s + 60)
    if proc.returncode != 0:
        g.error = _clean_error(proc)
        return
    before, _, after = proc.stdout.partition(_MARK + "\n")
    g.output = before.strip("\n")
    g.checks = _parse_checks(after)
    g.correct = bool(g.checks) and all(ok for _, ok, _ in g.checks)


def _grade_duck_lab(q: Question, g: "Grade", on_status: Optional[Callable[[str], None]]) -> None:
    lake = _lake()
    lake.require_lake()
    if not lake.lab_is_set_up(q):
        if on_status:
            on_status("Setting up the lab...")
        lake.setup_lab(q)
        g.error = "The lab wasn't set up yet, so it has just been created for you. Do the task, then check again."
        return
    if on_status:
        on_status("Checking the files in lake/ ...")
    g.checks = lake.run_checks(q.check_path.read_text(encoding="utf-8"))
    g.correct = bool(g.checks) and all(ok for _, ok, _ in g.checks)


_STEP = "[dojo] "


def _grade_pipeline(q: Question, sql: str, check_sql: str, g: "Grade", timeout_s: int,
                    on_status: Optional[Callable[[str], None]]) -> None:
    if not split_statements(sql):
        raise QueryError("no SQL found (the file only has comments)")
    session = f"SET application_name = '{APP_NAME}';\nSET statement_timeout = '{timeout_s}s';\n"
    head = [session, f"\\pset null '{NULL}'"]
    parts, runs, last_data, outputs = list(head), 0, "setup", []

    def run_segment() -> bool:
        """Run the accumulated sequential steps in one psql session."""
        nonlocal parts
        proc = psql("\n".join(parts) + "\n", timeout=timeout_s * max(1, runs) + 120)
        outputs.append(proc.stdout)
        parts = list(head)
        if proc.returncode != 0:
            steps = [ln[len(_STEP):] for ln in proc.stdout.splitlines() if ln.startswith(_STEP)]
            g.error = (f"Failed during: {steps[-1]}\n" if steps else "") + _clean_error(proc)
            return False
        return True

    if on_status:
        on_status("Replaying the pipeline: " + " → ".join(map(step_label, q.plan)))
    for step in q.plan:
        if step == "setup":
            parts += [f"\\echo '{_STEP}resetting the lab'", "SET client_min_messages = warning;",
                      q.setup_path.read_text(encoding="utf-8"), ";",
                      _LABS_TABLE, f"INSERT INTO _dojo.labs VALUES ({q.id}, now()) "
                      "ON CONFLICT (question_id) DO UPDATE SET set_up_at = now();", "RESET client_min_messages;"]
        elif step == "answer":
            runs += 1
            parts += [f"\\echo '{_STEP}your script, run {runs} (after {last_data})'", sql, ";",
                      "RESET ALL;", session]  # your SETs don't leak into the next step
        elif step == "check":
            parts += [f"\\echo {_MARK}", "\\pset format csv", check_sql, ";"]
        elif step.startswith("parallel:"):
            name, n = parallel_step(step)
            if not run_segment():
                return
            if on_status:
                on_status(f"Running {n} concurrent sessions of {name}...")
            outputs.append(f"{_STEP}{n} concurrent sessions of {name}\n")
            error = _run_parallel(q.dir / f"{name}.sql", n, timeout_s)
            if error:
                g.error = f"Failed during: {name} ({n} concurrent sessions)\n{error}"
                g.output = "".join(outputs).strip("\n")
                return
            last_data = name
        else:
            last_data = step
            parts += [f"\\echo '{_STEP}running {step}'", (q.dir / f"{step}.sql").read_text(encoding="utf-8"), ";"]
    ok = run_segment()
    full = "".join(outputs)
    before, _, after = full.partition(_MARK + "\n")
    g.output = before.strip("\n")
    if ok:
        g.checks = _parse_checks(after)
        g.correct = bool(g.checks) and all(ok for _, ok, _ in g.checks)


_BARRIER_TABLE = "CREATE TABLE IF NOT EXISTS _dojo.barrier (run text NOT NULL, session int NOT NULL);"


def _run_parallel(path: Path, n: int, timeout_s: int) -> Optional[str]:
    """Run a step file in n concurrent psql sessions (psql variable :worker = 1..n).
    Returns the errors, or None."""
    run = os.urandom(8).hex()
    # Starting a session can take a second (docker compose exec), so they wait for each other
    # before running the step: otherwise the first one could be done before the last connects.
    # The table is created here, once: concurrent CREATE TABLE IF NOT EXISTS can collide.
    proc = psql(f"SET client_min_messages = warning;\n{_BARRIER_TABLE}\n")
    if proc.returncode != 0:
        return _clean_error(proc)
    barrier = (f"INSERT INTO _dojo.barrier VALUES ('{run}', :worker);\n"
               "DO $$ BEGIN\n"
               "  FOR i IN 1..3000 LOOP  -- at most 30 s\n"
               f"    EXIT WHEN (SELECT count(*) FROM _dojo.barrier WHERE run = '{run}') >= {n};\n"
               "    PERFORM pg_sleep(0.01);\n"
               "  END LOOP;\n"
               "END $$;\n")
    script = (f"SET application_name = '{APP_NAME}';\n{barrier}SET statement_timeout = '{timeout_s}s';\n"
              + path.read_text(encoding="utf-8"))
    procs = []
    for i in range(1, n + 1):
        cmd = psql_cmd() + ["-X", "-q", "-v", "ON_ERROR_STOP=1", "-v", f"worker={i}", "-f", "-"]
        procs.append(subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                      text=True, encoding="utf-8"))
    for proc in procs:  # start them all, then feed them, so they really overlap
        try:
            proc.stdin.write(script)
            proc.stdin.close()
        except BrokenPipeError:  # it exited already (can't connect?): its stderr says why
            pass
    errors: Dict[str, List[int]] = {}  # message -> sessions that hit it
    for i, proc in enumerate(procs, start=1):
        try:
            _, err = proc.communicate(timeout=timeout_s + 60)
        except subprocess.TimeoutExpired:
            proc.kill()
            errors.setdefault("timed out", []).append(i)
            continue
        if proc.returncode != 0:
            msg = re.sub(r"^psql:<stdin>:\d+: ", "", err.strip(), flags=re.M) or f"exit code {proc.returncode}"
            errors.setdefault(msg, []).append(i)
    psql(f"DELETE FROM _dojo.barrier WHERE run = '{run}';")
    out = []
    for msg, sessions in errors.items():
        who = f"session {sessions[0]}" if len(sessions) == 1 else "sessions " + ", ".join(map(str, sessions))
        out.append(f"{who} of {n} failed:\n{msg}")
    return "\n".join(out) if out else None


# --------------------------------------------------------------------------- #
# Objects you created (indexes, views, ...) and resetting them
# --------------------------------------------------------------------------- #
def user_objects() -> List[Tuple[str, str, str]]:
    """(kind, name, drop statement) for everything beyond the baseline dataset."""
    tables = "ARRAY['" + "','".join(DATASET_TABLES) + "']"
    try:
        return [tuple(r) for r in query_rows(f"""
            SELECT 'index', indexname, format('DROP INDEX IF EXISTS public.%I', indexname)
            FROM pg_indexes
            WHERE schemaname = 'public' AND tablename = ANY ({tables})
              AND indexname NOT IN (SELECT name FROM _dojo.baseline_objects)
            UNION ALL
            SELECT 'statistics', stxname, format('DROP STATISTICS IF EXISTS public.%I', stxname)
            FROM pg_statistic_ext s JOIN pg_namespace n ON n.oid = s.stxnamespace
            WHERE n.nspname = 'public'
            UNION ALL
            SELECT 'materialized view', matviewname,
                   format('DROP MATERIALIZED VIEW IF EXISTS public.%I CASCADE', matviewname)
            FROM pg_matviews WHERE schemaname = 'public'
            UNION ALL
            SELECT 'view', viewname, format('DROP VIEW IF EXISTS public.%I CASCADE', viewname)
            FROM pg_views WHERE schemaname = 'public' AND viewname NOT LIKE 'pg_stat_statements%'
            UNION ALL
            SELECT 'table', tablename, format('DROP TABLE IF EXISTS public.%I CASCADE', tablename)
            FROM pg_tables WHERE schemaname = 'public' AND tablename <> ALL ({tables});""")
            if len(r) == 3]
    except QueryError:
        return []


def reset_objects(objs: List[Tuple[str, str, str]]) -> None:
    proc = psql("\n".join(stmt + ";" for _, _, stmt in objs) + "\nANALYZE;\n")
    if proc.returncode != 0:
        raise DojoError(_clean_error(proc))


def fmt_ms(ms: float) -> str:
    return f"{ms:.1f} ms" if ms < 1000 else f"{ms / 1000:.2f} s"
