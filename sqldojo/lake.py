"""Level 8: a data lake in ./lake, queried with DuckDB.

The duckdb package is the only dependency (it lives in ./.venv; the launcher installs it the first
time it's needed). The raw "landing zone" is exported from Postgres with psql COPY, so no DuckDB
extensions are downloaded.
"""
from __future__ import annotations

import datetime as dt
import decimal
import gzip
import json
import os
import re
import shutil
import subprocess
import threading
import time
from pathlib import Path
from typing import Callable, List, Optional, Tuple

from . import core
from .core import NULL, DojoError, QueryError, Result

LAKE = core.ROOT / "lake"
DB_FILE = LAKE / "lake.duckdb"
STAMP = LAKE / ".built.json"
LABS_DIR = LAKE / ".labs"
_active: set = set()

# Tables exported as single files into lake/raw/
_SMALL_TABLES = ["users", "products", "categories", "orders", "order_items"]


def _duckdb():
    try:
        import duckdb
    except ImportError:
        raise core.NeedsDuckDB()
    return duckdb


def connect():
    duckdb = _duckdb()
    LAKE.mkdir(exist_ok=True)
    os.chdir(core.ROOT)  # paths in questions are relative to the repo: lake/raw/...
    con = duckdb.connect(str(DB_FILE))
    con.execute("SET TimeZone = 'UTC'")
    return con


def _text(v) -> str:
    if v is None:
        return NULL
    if isinstance(v, bool):
        return "t" if v else "f"
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, (dt.datetime, dt.date, decimal.Decimal)):
        return str(v)
    return str(v)


class _Guard:
    """Interrupt a DuckDB query after a timeout, and let cancel() reach it."""

    def __init__(self, con, timeout_s: int):
        self.con, self.timer = con, threading.Timer(timeout_s, con.interrupt)

    def __enter__(self):
        _active.add(self.con)
        self.timer.start()
        return self

    def __exit__(self, *exc):
        self.timer.cancel()
        _active.discard(self.con)
        self.con.close()


def _error(e: Exception, timeout_s: int) -> QueryError:
    msg = str(e)
    if "INTERRUPT" in msg.upper():
        msg = f"Cancelled (or ran longer than {timeout_s}s)."
    return QueryError(msg)


def run_query(sql: str, timeout_s: int = core.DEFAULT_TIMEOUT_S) -> Result:
    body = core.strip_sql(sql)
    if not body:
        raise QueryError("no SQL found (the file only has comments)")
    duckdb = _duckdb()
    con = connect()
    with _Guard(con, timeout_s):
        try:
            start = time.perf_counter()
            cur = con.execute(body)
            if cur.description is None:
                raise QueryError("the statement returned no result set (is it a SELECT?)")
            rows = cur.fetchall()
            ms = (time.perf_counter() - start) * 1000
        except duckdb.Error as e:
            raise _error(e, timeout_s)
        return Result([d[0] for d in cur.description], [[_text(v) for v in r] for r in rows], ms)


def run_scratch(sql: str, limit: int, timeout_s: int = core.DEFAULT_TIMEOUT_S) -> Result:
    """Run one exploratory statement; fetch at most `limit` rows."""
    body = core.strip_sql(sql)
    if not body:
        raise QueryError("no SQL found (only comments)")
    duckdb = _duckdb()
    con = connect()
    with _Guard(con, timeout_s):
        try:
            start = time.perf_counter()
            cur = con.execute(body)
            rows = cur.fetchmany(limit + 1) if cur.description else []
            ms = (time.perf_counter() - start) * 1000
        except duckdb.Error as e:
            raise _error(e, timeout_s)
        if cur.description is None:
            return Result([], [], ms)
        return Result([d[0] for d in cur.description], [[_text(v) for v in r] for r in rows[:limit]], ms,
                      len(rows) > limit)


def _table(cur, limit: int = 40) -> str:
    header = [d[0] for d in cur.description]
    rows = cur.fetchmany(limit + 1)
    cells = [[_text(v).replace(NULL, "NULL") for v in r] for r in rows[:limit]]
    widths = [max([len(h)] + [min(len(r[i]), 50) for r in cells]) for i, h in enumerate(header)]
    out = [" | ".join(h.ljust(w) for h, w in zip(header, widths)),
           "-+-".join("-" * w for w in widths)]
    out += [" | ".join((c if len(c) <= 50 else c[:47] + "...").ljust(w) for c, w in zip(r, widths)) for r in cells]
    out.append(f"({len(cells)}{'+' if len(rows) > limit else ''} rows)")
    return "\n".join(out)


def run_script(sql: str, timeout_s: int = core.DEFAULT_TIMEOUT_S) -> str:
    """Run every statement; return a psql-like transcript."""
    stmts = core.split_statements(sql)
    if not stmts:
        raise QueryError("no SQL found (the file only has comments)")
    duckdb = _duckdb()
    con = connect()
    out = []
    with _Guard(con, timeout_s):
        for st in stmts:
            out.append(st + ";")
            start = time.perf_counter()
            try:
                cur = con.execute(st)
                out.append(_table(cur) if cur.description else "OK")
            except duckdb.Error as e:
                out.append("ERROR: " + str(_error(e, timeout_s)))
                raise QueryError("\n".join(out))
            out.append(f"Time: {(time.perf_counter() - start) * 1000:.1f} ms")
    return "\n".join(out)


def explain(sql: str, analyze: bool = True, timeout_s: int = core.DEFAULT_TIMEOUT_S) -> str:
    body = core.strip_sql(sql)
    duckdb = _duckdb()
    con = connect()
    with _Guard(con, timeout_s):
        try:
            rows = con.execute(("EXPLAIN ANALYZE " if analyze else "EXPLAIN ") + body).fetchall()
        except duckdb.Error as e:
            raise _error(e, timeout_s)
    return "\n".join(r[-1] for r in rows)


def files_read(sql: str, timeout_s: int = core.DEFAULT_TIMEOUT_S) -> int:
    """How many files the query scanned, according to DuckDB's profiler."""
    plan = explain(sql, analyze=True, timeout_s=timeout_s)
    # the number can wrap onto the next line inside the plan's box drawing
    return sum(int(n) for n in re.findall(r"Total Files Read:[\s│]*(\d+)", plan.replace(",", "")))


def cancel() -> None:
    for con in list(_active):
        try:
            con.interrupt()
        except Exception:
            pass


def count_files(pattern: str) -> int:
    return len(list(core.ROOT.glob(pattern)))


# --------------------------------------------------------------------------- #
# Building the lake
# --------------------------------------------------------------------------- #
def status() -> Optional[dict]:
    try:
        return json.loads(STAMP.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def is_stale(meta: dict) -> bool:
    st = status()
    return bool(st) and st.get("generated_at") != meta.get("generated_at")


def _export(sql: str, dest: Path) -> None:
    """Stream COPY (sql) TO STDOUT through gzip into dest."""
    cmd = core.psql_cmd() + ["-X", "-q", "-v", "ON_ERROR_STOP=1", "-c",
                             f"COPY ({sql}) TO STDOUT WITH (FORMAT csv, HEADER true)"]
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    with gzip.open(tmp, "wb", compresslevel=1) as out:
        shutil.copyfileobj(proc.stdout, out, 1 << 20)
    err = proc.stderr.read().decode("utf-8", "replace")
    if proc.wait() != 0:
        tmp.unlink(missing_ok=True)
        raise DojoError(f"exporting from Postgres failed:\n{err.strip()}")
    tmp.replace(dest)


def build(on_line: Callable[[str], None], rebuild: bool = False) -> dict:
    """Export the Postgres dataset into lake/raw (the landing zone)."""
    meta = core.require_db()
    if status() and not rebuild:
        return status()
    _duckdb()
    if LAKE.exists():
        for child in LAKE.iterdir():  # keep nothing: silver/gold built from old data would be wrong
            shutil.rmtree(child) if child.is_dir() else child.unlink()
    raw, staging = LAKE / "raw", LAKE / "_staging"
    raw.mkdir(parents=True)
    staging.mkdir()
    start = time.time()
    for t in _SMALL_TABLES:
        on_line(f"--> lake/raw/{t}.csv.gz")
        _export(f"SELECT * FROM {t}", raw / f"{t}.csv.gz")
    on_line("--> lake/raw/events/day=YYYY-MM-DD/ (one gzipped CSV per day; the big one)")
    _export("SELECT * FROM events ORDER BY event_id", staging / "events.csv.gz")
    con = connect()
    try:
        con.execute(f"""
            COPY (SELECT *, occurred_at::date AS day FROM read_csv('{staging / "events.csv.gz"}'))
            TO 'lake/raw/events' (FORMAT csv, COMPRESSION gzip, PARTITION_BY (day),
                                  WRITE_PARTITION_COLUMNS false, FILENAME_PATTERN 'events_{{i}}')""")
        events = con.execute(f"SELECT count(*) FROM read_csv('{staging / 'events.csv.gz'}')").fetchone()[0]

        on_line("--> lake/raw/partner_orders/*.json (a partner feed whose schema drifts)")
        (raw / "partner_orders").mkdir()
        for month in range(1, 13):
            m = f"2025-{month:02d}"
            fields = (
                "o.order_id, o.created_at AS ts, round(t.total, 2) AS total, o.ship_country AS country"
                if month <= 6 else
                "o.order_id, o.created_at AS ts, round(t.total, 2) AS amount_usd, o.ship_country AS country, "
                "CASE WHEN o.device = 'mobile' THEN 'app' ELSE 'web' END AS channel"
                if month <= 9 else
                "o.order_id, strftime(o.created_at, '%Y-%m-%dT%H:%M:%SZ') AS ts, "
                "round(t.total, 2) AS amount_usd, o.ship_country AS country, "
                "CASE WHEN o.device = 'mobile' THEN 'app' WHEN o.order_id % 10 = 0 THEN 'marketplace' ELSE 'web' END AS channel")
            con.execute(f"""
                COPY (SELECT {fields}
                      FROM read_csv('lake/raw/orders.csv.gz') o
                      JOIN (SELECT order_id, sum(quantity * unit_price) AS total
                            FROM read_csv('lake/raw/order_items.csv.gz') GROUP BY order_id) t USING (order_id)
                      WHERE o.created_at >= TIMESTAMPTZ '{m}-01' AND o.created_at < TIMESTAMPTZ '{m}-01' + INTERVAL 1 MONTH
                        AND o.ship_country IN ('DE', 'FR', 'NL', 'ES')
                      ORDER BY o.order_id)
                TO 'lake/raw/partner_orders/{m}.json' (FORMAT json)""")

        on_line("--> lake/raw/corrections/ (late corrections: bot traffic to remove)")
        (raw / "corrections").mkdir()
        con.execute("""
            COPY (SELECT e.event_id
                  FROM read_csv('lake/raw/events/*/*.csv.gz', hive_partitioning = true) e
                  JOIN read_csv('lake/raw/users.csv.gz') u ON u.user_id = e.user_id
                  WHERE u.is_test AND e.day >= DATE '2025-11-01' AND e.day < DATE '2025-12-01'
                  ORDER BY e.event_id)
            TO 'lake/raw/corrections/bot_events_2025-11.csv' (FORMAT csv, HEADER true)""")
    finally:
        con.close()
    shutil.rmtree(staging)
    stamp = {"generated_at": meta.get("generated_at"), "scale": meta.get("scale"),
             "events": events, "built_at": core.now_iso()}
    STAMP.write_text(json.dumps(stamp, indent=2) + "\n", encoding="utf-8")
    on_line(f"Lake ready in {time.time() - start:.0f}s: {events:,} events in lake/raw/.")
    return stamp


def require_lake() -> dict:
    st = status()
    if not st:
        raise DojoError("the lake hasn't been built yet. Run: ./dojo lake")
    return st


# --------------------------------------------------------------------------- #
# Lab support (DuckDB labs keep their markers next to the lake)
# --------------------------------------------------------------------------- #
def lab_is_set_up(q: core.Question) -> bool:
    return (q.setup_path is None and not q.lake_paths) or (LABS_DIR / str(q.id)).exists()


def setup_lab(q: core.Question) -> None:
    require_lake()
    for rel in q.lake_paths:
        target = (core.ROOT / rel).resolve()
        if LAKE.resolve() not in target.parents:
            raise DojoError(f"lake_paths must be inside lake/: {rel}")
        if target.is_dir():
            shutil.rmtree(target)
        elif target.exists():
            target.unlink()
        target.parent.mkdir(parents=True, exist_ok=True)
    if q.setup_path is None:
        LABS_DIR.mkdir(parents=True, exist_ok=True)
        (LABS_DIR / str(q.id)).write_text(core.now_iso() + "\n", encoding="utf-8")
        return
    try:
        run_script(q.setup_path.read_text(encoding="utf-8"), timeout_s=3600)
    except QueryError as e:
        raise DojoError(f"setting up the lab failed:\n{e}")
    frozen = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc).timestamp()
    for rel in q.freeze_mtimes:
        for f in (core.ROOT / rel).rglob("*"):
            if f.is_file():
                os.utime(f, (frozen, frozen))
    LABS_DIR.mkdir(parents=True, exist_ok=True)
    (LABS_DIR / str(q.id)).write_text(core.now_iso() + "\n", encoding="utf-8")


def run_checks(check_sql: str, timeout_s: int = 600) -> List[Tuple[str, bool, str]]:
    duckdb = _duckdb()
    stmts = core.split_statements(check_sql)
    con = connect()
    with _Guard(con, timeout_s):
        try:
            for st in stmts[:-1]:
                con.execute(st)
            cur = con.execute(stmts[-1])
            rows = cur.fetchall()
        except duckdb.Error as e:
            raise _error(e, timeout_s)
    out = []
    for r in rows:
        detail = "" if len(r) < 3 or r[2] is None else str(r[2])
        out.append((str(r[0]), bool(r[1]), detail if len(detail) <= 200 else detail[:197] + "..."))
    return out
