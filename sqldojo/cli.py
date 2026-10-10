"""The `./dojo <command>` interface. Standard library only."""
from __future__ import annotations

import argparse
import os
import re
import signal
import sys
import time

from . import core
from .core import DojoError, QueryError

_COLOR = sys.stdout.isatty() and not os.environ.get("NO_COLOR")


def _c(code: str, s: str) -> str:
    return f"\033[{code}m{s}\033[0m" if _COLOR else s


def bold(s): return _c("1", s)
def dim(s): return _c("2", s)
def red(s): return _c("31", s)
def green(s): return _c("32", s)
def yellow(s): return _c("33", s)
def cyan(s): return _c("36", s)


def confirm(prompt: str, assume_yes: bool) -> bool:
    if assume_yes:
        return True
    if not sys.stdin.isatty():
        return False
    return input(f"{prompt} [y/N] ").strip().lower() in ("y", "yes")


def print_question(q: core.Question) -> None:
    solved = core.is_solved(core.load_progress(), q)
    print(bold(cyan(f"Q{q.code} · {q.title}")) + (green("  ✔ solved") if solved else ""))
    print(dim(f"Level {q.level} · {q.level_name}  |  {', '.join(q.topics)}"))
    if q.tables:
        print(dim("Tables: " + ", ".join(q.tables)))
    if q.is_perf:
        print(yellow(f"Performance target: {q.target_label()}"))
    if q.kind == "script":
        print(yellow(f"Lab: your answer is a script, run as role {q.run_as} in a transaction that is rolled back."))
    elif q.kind == "state":
        print(yellow(f"Lab: change the database (./dojo psql, or ./dojo run {q.id} runs your scratch file), "
                     f"then check. Start over with ./dojo lab-reset {q.id}."))
    elif q.kind == "pipeline":
        print(yellow("Pipeline lab: check replays " + " → ".join("YOUR LOAD" if st == "answer" else st for st in q.plan)))
        print(yellow(f"  Develop step by step: ./dojo lab-step {q.id} setup | "
                     + " | ".join(f"./dojo lab-step {q.id} {st}" for st in q.steps[:2])
                     + (" ..." if len(q.steps) > 2 else "") + f", then ./dojo run {q.id}"))
    print()
    print(q.prompt)
    print()
    print(dim(f"Answer: answers/{q.code}.sql   run: ./dojo run {q.id}   check: ./dojo check {q.id}   "
              f"hint: ./dojo hint {q.id} ({len(q.hints)} available)"))


def print_table(res: core.Result, limit: int) -> None:
    rows = [["NULL" if v == core.NULL else v for v in r] for r in res.rows[:limit]]
    widths = [len(h) for h in res.header]
    for r in rows:
        widths = [max(w, min(len(v), 60)) for w, v in zip(widths, r)]

    def cell(v, w):
        return (v if len(v) <= 60 else v[:57] + "...").ljust(w)

    print(" | ".join(bold(h.ljust(w)) for h, w in zip(res.header, widths)))
    print("-+-".join("-" * w for w in widths))
    for r in rows:
        print(" | ".join(cell(v, w) for v, w in zip(r, widths)))
    more = f", showing {limit}" if len(res.rows) > limit else ""
    print(dim(f"({len(res.rows)} rows{more}, {core.fmt_ms(res.ms)})"))


def read_answer(q: core.Question, file_arg=None) -> str:
    path = core.Path(file_arg) if file_arg else q.answer_path
    if not path.exists():
        raise DojoError(f"{path} does not exist. Start with: ./dojo start {q.id}")
    return path.read_text(encoding="utf-8")


# --------------------------------------------------------------------------- #
def cmd_up(args):
    if core.using_custom_psql():
        raise DojoError("DOJO_PSQL is set, so you manage the database yourself. Use ./dojo generate.")
    print(bold("Starting Postgres..."))
    core.start_database(print)
    meta = core.db_meta()
    if meta:
        print(green(f"Ready. Dataset scale={meta.get('scale')} generated {meta.get('generated_at', '')[:19]}."))
        if args.scale is not None and float(args.scale) != float(meta.get("scale", 0)):
            print(yellow(f"The data was generated at scale {meta.get('scale')}. "
                         f"To change it: ./dojo generate --scale {args.scale:g}"))
        return
    generate(args.scale if args.scale is not None else 1.0, args.force)


def cmd_generate(args):
    meta = core.db_meta()
    if meta and not confirm(f"This replaces the current dataset (scale={meta.get('scale')}) and drops "
                            "any indexes/tables you created. Continue?", args.yes):
        raise DojoError("aborted (use --yes to skip this prompt)")
    generate(args.scale, args.force)


def generate(scale: float, force: bool = False):
    print(bold(f"Generating the dataset at scale {scale:g} "
               f"(~{5.8 * scale:.1f}M events, ~{0.8 * scale:.1f} GB on disk, ~{0.75 * scale:.1f} min)."))
    if scale >= 5:
        print(yellow("Large scales take a while. Grab a coffee."))
    start = time.time()
    core.generate_data(scale, print, force=force)
    print(green(f"Done in {time.time() - start:.0f}s.") + " Start practising: ./dojo  (or ./dojo today)")


def cmd_down(args):
    core.stream(core.COMPOSE + ["stop"], print)


def cmd_destroy(args):
    if not confirm("Delete the container AND its data volume?", args.yes):
        raise DojoError("aborted")
    core.stream(core.COMPOSE + ["down", "-v"], print)


def cmd_psql(args):
    cmd = core.psql_cmd(interactive=True)
    os.execvp(cmd[0], cmd)


def cmd_status(args):
    qs = core.load_questions()
    progress = core.load_progress()
    meta = core.db_meta()
    if meta:
        print(bold("Database") + f"  scale={meta.get('scale')}  generated={meta.get('generated_at', '')[:19]}")
        for name, rows, size in core.table_stats():
            print(f"  {name:<22} {rows:>14} rows  {size:>9}")
        extra = core.user_objects()
        if extra:
            print(bold("Objects you created") + dim("  (./dojo reset removes them)"))
            for kind, name, _ in extra:
                print(f"  {kind:<18} {name}")
    else:
        print(yellow("Database not running or not generated. Run: ./dojo up"))
    print()
    solved = sum(core.is_solved(progress, q) for q in qs)
    print(bold("Progress") + f"  {solved}/{len(qs)} solved")
    for lvl, name in core.LEVELS.items():
        lq = [q for q in qs if q.level == lvl]
        if lq:
            s = sum(core.is_solved(progress, q) for q in lq)
            print(f"  {lvl}. {name:<20} {'█' * s}{'░' * (len(lq) - s)} {s}/{len(lq)}")


def cmd_list(args):
    progress = core.load_progress()
    current = None
    for q in core.load_questions():
        if q.level != current:
            current = q.level
            print()
            print(bold(f"Level {q.level} · {q.level_name}"))
        p = progress.get(q.code, {})
        mark = green("✔") if core.is_solved(progress, q) else (yellow("…") if p.get("attempts") else " ")
        perf = yellow(" ⏱") if q.is_perf else ""
        print(f"  {mark} {q.id:>3}  {q.title}{perf}  " + dim(", ".join(q.topics)))
    print()


def cmd_next(args):
    if args.id_only:  # used by the daily-question workflow
        exclude = {int(x) for x in re.split(r"[\s,]+", args.exclude or "") if x.strip()}
        q = core.next_question(exclude)
        if q:
            print(q.id)
        return
    q = core.resume_question()
    if q is None:
        print(green("You've solved every question. 🎉 Add your own in questions/ (see CONTRIBUTING.md)."))
        return
    start_question(q)


def cmd_start(args):
    start_question(core.get_question(args.question))


def start_question(q: core.Question):
    created = core.ensure_stub(q)
    core.remember_question(q)
    print_question(q)
    if created:
        print(dim(f"Created answers/{q.code}.sql"))
    if q.setup_path and core.db_meta() and not core.lab_is_set_up(q):
        core.setup_lab(q)
        print(dim("Lab objects created."))


def cmd_lab_step(args):
    q = core.get_question(args.question)
    if q.kind != "pipeline":
        raise DojoError(f"Q{q.code} is not a pipeline lab (use ./dojo lab-reset {q.id})")
    core.require_db()
    print(core.run_lab_step(q, args.step))


def cmd_lab_reset(args):
    q = core.get_question(args.question)
    if q.setup_path is None:
        raise DojoError(f"Q{q.code} has no lab to reset")
    core.require_db()
    core.setup_lab(q)
    print(green(f"Lab for Q{q.code} reset."))


def cmd_show(args):
    print_question(core.get_question(args.question))


def cmd_hint(args):
    q = core.get_question(args.question)
    if not q.hints:
        print("This question has no hints. You've got this.")
        return
    shown = core.reveal_hint(q, all_hints=args.all)
    for i, h in enumerate(shown, start=1):
        print(f"{bold(f'Hint {i}/{len(q.hints)}:')} {h}")
    if len(shown) < len(q.hints):
        print(dim("Run again for the next hint."))


def cmd_run(args):
    q = core.get_question(args.target) if args.target.isdigit() else None
    sql = read_answer(q) if q else core.Path(args.target).read_text(encoding="utf-8")
    core.require_db()
    if (q and q.is_lab) or args.script:
        print(core.run_script(sql, timeout_s=args.timeout))
        return
    print_table(core.run_query(sql, timeout_s=args.timeout), args.limit)


_KIND_STYLE = {"error": red, "warn": yellow, "info": dim, "row": lambda s: "    " + s}


def cmd_check(args):
    q = core.get_question(args.question)
    # state labs check the database itself; the answer file is only a scratchpad
    sql = "" if q.kind == "state" and not args.file and not q.answer_path.exists() else read_answer(q, args.file)
    print(bold(cyan(f"Q{q.code} · {q.title}")))
    g = core.grade(q, sql, timeout_s=args.timeout, on_status=lambda s: print(dim("  " + s)))
    if g.error:
        print(red({"query": "✘ Your query failed:", "script": "✘ Your script failed:"}.get(q.kind, "✘ Not checked:")))
        print("  " + g.error.replace("\n", "\n  "))
        sys.exit(1)
    if q.is_lab:
        if g.output:
            print(dim("  your script printed:"))
            print(dim("    " + "\n    ".join(g.output.splitlines()[:20])))
        for name, ok, detail in g.checks:
            print(f"  {green('✔') if ok else red('✘')} {name}" + (dim(f"  ({detail})") if detail else ""))
        if g.passed:
            print(green("✔ Lab complete!") + dim(f"  attempt {g.attempts}"))
            if g.first_solve:
                print(dim(f"  Read the explanation: ./dojo solution {q.id}"))
        else:
            print(red("✘ Not yet."))
        sys.exit(0 if g.passed else 1)
    runs = f"  (best of {len(g.timings)})" if len(g.timings) > 1 else ""
    print(f"  yours      {len(g.actual.rows):>7} rows  {core.fmt_ms(g.best_ms):>10}" + dim(runs))
    print(dim(f"  reference  {len(g.expected.rows):>7} rows  {core.fmt_ms(g.expected.ms):>10}"))
    for kind, text in g.messages:
        print("  " + _KIND_STYLE.get(kind, str)(text))
    if g.correct and not g.fast_enough:
        print(yellow(f"✔ Correct result, but too slow: {core.fmt_ms(g.best_ms)} > target {core.fmt_ms(g.target_ms)}."))
        print(dim(f"  Look at the plan: ./dojo explain {q.id}"))
    elif g.passed:
        target = f" (target {core.fmt_ms(g.target_ms)})" if g.target_ms else ""
        hints = f", {g.hints} hint{'s' if g.hints != 1 else ''}" if g.hints else ", no hints"
        print(green(f"✔ Correct!{target}") + dim(f"  attempt {g.attempts}{hints}"))
        if g.first_solve:
            print(dim(f"  Compare with the reference solution: ./dojo solution {q.id}"))
            print(dim(f"  Commit it: git add answers && git commit -m 'Solve Q{q.code}'"))
    else:
        print(red("✘ Not quite."))
        if len(core.revealed_hints(q)) < len(q.hints):
            print(dim(f"  Stuck? ./dojo hint {q.id}"))
    sys.exit(0 if g.passed else 1)


def cmd_solution(args):
    q = core.get_question(args.question)
    if not core.is_solved(core.load_progress(), q) and not confirm(
            "You haven't solved this one yet. Reveal the solution anyway?", args.yes):
        raise DojoError("aborted. (Try ./dojo hint first.)")
    core.mark_solution_viewed(q)
    print(q.solution_path.read_text(encoding="utf-8"))


def cmd_explain(args):
    q = core.get_question(args.question)
    if q.is_lab:
        raise DojoError("explain works on single queries. In a lab, put EXPLAIN in your script.")
    sql = read_answer(q, args.file)
    core.require_db()
    print(core.explain(sql, analyze=not args.no_analyze, timeout_s=args.timeout))
    print(dim("Tip: paste the plan into https://explain.dalibo.com for a visual version."))


def cmd_reset(args):
    core.require_db()
    objs = core.user_objects()
    if not objs:
        print("Nothing to reset: only the baseline indexes exist.")
        return
    for kind, name, _ in objs:
        print(f"  drop {kind} {name}")
    if not confirm("Drop these objects?", args.yes):
        raise DojoError("aborted")
    core.reset_objects(objs)
    print(green("Back to baseline."))


def cmd_selftest(args):
    """Run every reference query. Used by CI and handy after editing questions."""
    meta = core.require_db()
    failures = 0
    only = {int(x) for x in args.only.split(",")} if args.only else None
    for q in core.load_questions():
        if only and q.id not in only:
            continue
        problems, detail = [], ""
        if not q.hints:
            problems.append("no hints")
        if not q.solution_path.exists():
            problems.append("missing solution.sql")
        try:
            if q.is_lab:
                detail = selftest_lab(q)
            else:
                if q.ordered and not re.search(r"order\s+by", core.strip_sql(q.expected_path.read_text()), re.I):
                    problems.append("ordered: true but the reference has no ORDER BY")
                if q.setup_path:
                    core.setup_lab(q)
                res = core.reference_result(q, meta, refresh=True)
                if not res.rows:
                    problems.append("reference returns no rows")
                detail = f"{len(res.rows):>6} rows  {core.fmt_ms(res.ms):>10}"
        except DojoError as e:
            problems.append(str(e).splitlines()[-1] if str(e).strip() else repr(e))
        if problems:
            failures += 1
            print(red(f"✘ {q.code} {q.title}: " + "; ".join(problems)))
        else:
            print(green(f"✔ {q.code}") + f" {q.title:<45} {detail}")
    if failures:
        raise DojoError(f"{failures} question(s) failed the self-test")
    print(green("All reference queries OK."))


def selftest_lab(q: core.Question) -> str:
    """The reference solution must pass the checks, and doing nothing must not."""
    solution = q.solution_path.read_text(encoding="utf-8")
    core.setup_lab(q)
    if q.kind == "state":
        g = core.grade(q, "", record=False)
        if g.passed:
            raise DojoError("the checks pass before doing anything")
        core.run_script(solution)
    else:
        g = core.grade(q, "SELECT 1", record=False)
        if g.passed:
            raise DojoError("the checks pass for a script that does nothing")
    g = core.grade(q, solution, record=False)
    core.setup_lab(q)  # leave a fresh lab behind
    if not g.passed:
        failed = [name for name, ok, _ in g.checks if not ok]
        raise DojoError("the solution fails: " + (g.error or ", ".join(failed)))
    return f"{len(g.checks):>3} checks pass"


def cmd_issue(args):
    """Markdown body for the daily GitHub issue."""
    q = core.get_question(args.question)
    out = [q.markdown(heading=False), ""]
    for i, h in enumerate(q.hints, start=1):
        out.append(f"<details><summary>Hint {i}</summary>\n\n{h}\n\n</details>\n")
    out += ["---", "**Practise:** run `./dojo` and pick this question, or from the shell:", "```bash",
            "./dojo up                # first time: starts Postgres and generates the data",
            f"./dojo start {q.id:<12}# creates answers/{q.code}.sql",
            f"./dojo check {q.id}", "```",
            "When it passes, commit and push `answers/`: the next daily run closes this issue."]
    print("\n".join(out))


def cmd_title(args):
    q = core.get_question(args.question)
    print(f"[Q{q.code}] {q.title}")


# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="dojo",
        description="SQL Dojo: daily SQL practice against a big, realistic Postgres dataset.\n"
                    "Run ./dojo with no command to open the terminal IDE.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""daily loop without the TUI:
  ./dojo today         show the next unsolved question and create answers/NNN.sql
  ./dojo run 7         run your answer and look at the output
  ./dojo check 7       grade it against the reference
  ./dojo hint 7        one more hint
  ./dojo solution 7    compare with the reference solution once solved""")
    sub = p.add_subparsers(dest="cmd", metavar="command")

    def add(name, fn, help_=None, aliases=()):
        kwargs = {"help": help_} if help_ else {}  # no help = hidden from the listing
        sp = sub.add_parser(name, aliases=list(aliases), **kwargs)
        sp.set_defaults(fn=fn)
        return sp

    add("tui", None, "open the terminal IDE (same as running ./dojo with no command)")
    sp = add("up", cmd_up, "start Postgres; generates the data on first run")
    sp.add_argument("--scale", type=float, help="dataset size (default 1 = ~6M events)")
    sp.add_argument("--force", action="store_true", help="skip the free-disk-space check")
    sp = add("generate", cmd_generate, "(re)generate the dataset")
    sp.add_argument("--scale", type=float, default=1.0)
    sp.add_argument("--force", action="store_true", help="skip the free-disk-space check")
    sp.add_argument("-y", "--yes", action="store_true")
    add("down", cmd_down, "stop Postgres (data is kept)")
    sp = add("destroy", cmd_destroy, "remove the container and its data")
    sp.add_argument("-y", "--yes", action="store_true")
    add("psql", cmd_psql, "open an interactive psql shell")
    add("status", cmd_status, "dataset info and your progress")
    add("list", cmd_list, "all questions", aliases=["ls"])
    sp = add("today", cmd_next, "pick up where you left off (or the next unsolved question)", aliases=["next"])
    sp.add_argument("--id-only", action="store_true", help=argparse.SUPPRESS)
    sp.add_argument("--exclude", help=argparse.SUPPRESS)
    sp = add("start", cmd_start, "start a specific question")
    sp.add_argument("question")
    sp = add("show", cmd_show, "print a question")
    sp.add_argument("question")
    sp = add("hint", cmd_hint, "reveal the next hint")
    sp.add_argument("question")
    sp.add_argument("--all", action="store_true")
    sp = add("run", cmd_run, "run your answer (or any .sql file) and print the result")
    sp.add_argument("target", help="question number or path to a .sql file")
    sp.add_argument("--limit", type=int, default=50)
    sp.add_argument("--timeout", type=int, default=core.DEFAULT_TIMEOUT_S)
    sp.add_argument("--script", action="store_true", help="run a multi-statement script (psql output)")
    sp = add("check", cmd_check, "grade your answer")
    sp.add_argument("question")
    sp.add_argument("--file", help="answer file (default answers/NNN.sql)")
    sp.add_argument("--timeout", type=int, default=core.DEFAULT_TIMEOUT_S)
    sp = add("solution", cmd_solution, "show the reference solution and explanation")
    sp.add_argument("question")
    sp.add_argument("-y", "--yes", action="store_true")
    sp = add("explain", cmd_explain, "EXPLAIN (ANALYZE, BUFFERS) your answer")
    sp.add_argument("question")
    sp.add_argument("--file")
    sp.add_argument("--no-analyze", action="store_true", help="plan only, don't execute")
    sp.add_argument("--timeout", type=int, default=core.DEFAULT_TIMEOUT_S)
    sp = add("lab-reset", cmd_lab_reset, "rebuild a lab's objects (Levels 6+)")
    sp.add_argument("question")
    sp = add("lab-step", cmd_lab_step, "run one step of a pipeline lab, e.g. batch_1 (Level 7)")
    sp.add_argument("question")
    sp.add_argument("step")
    sp = add("reset", cmd_reset, "drop indexes/views/tables you created")
    sp.add_argument("-y", "--yes", action="store_true")
    sp = add("selftest", cmd_selftest, "run every reference query (for CI / question authors)")
    sp.add_argument("--only", help="comma-separated question ids")
    sp = add("issue", cmd_issue)
    sp.add_argument("question")
    sp = add("title", cmd_title)
    sp.add_argument("question")
    add("help", lambda a: p.print_help(), "show this help")
    return p


def main(argv=None) -> None:
    if hasattr(signal, "SIGPIPE"):
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)  # `./dojo list | head` shouldn't traceback
    args = build_parser().parse_args(argv)
    try:
        args.fn(args)
    except DojoError as e:
        print(red("error: ") + str(e), file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
