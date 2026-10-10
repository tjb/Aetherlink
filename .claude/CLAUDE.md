# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

SQL Dojo: a self-hosted SQL learning tool. A deterministic generator builds a realistic e-commerce
dataset inside Postgres; a bank of graded questions (`questions/`) is solved in a Textual terminal
IDE (`./dojo`) or via a plain CLI (`./dojo <command>`). The owner is learning SQL in depth, so
explanations in solutions matter as much as the queries.

## Commands

```bash
./dojo                      # terminal IDE (bootstraps .venv with Textual on first run)
./dojo up                   # start Postgres 17 in Docker (port 5433) + generate data if missing
./dojo generate --scale 1 --yes
./dojo selftest [--only 7]  # run every reference query against the local data
./dojo check 7 --file questions/007-*/solution.sql
python3 -m unittest discover -s tests          # unit tests (no DB needed)
.venv/bin/python -m unittest tests/test_tui.py # headless TUI smoke test (needs DB)
```

To use a database other than the compose one, set `DOJO_PSQL="psql postgresql://..."` (CI does this).

## Layout

- `db/generate.sql`: the whole dataset generator, pure SQL driven by `psql -v scale=N`.
  Randomness comes from `_dojo.rnd(key, salt)` (hash-based), so output is identical for a
  given scale. Hidden helper objects live in schema `_dojo` (`_dojo.meta`, `_dojo.baseline_objects`).
  Don't name anything `dojo`: that's the DB role, and `search_path` would pick it up.
- `sqldojo/core.py`: questions, progress, psql runner, grading. **Standard library only**:
  the CLI must work with a bare `python3`.
- `sqldojo/cli.py`: argparse commands. `sqldojo/tui.py`: the Textual app (the only module that
  needs a third-party package; pinned in `requirements.txt`).
- `questions/NNN-slug/`: `question.md` (front matter + prompt + `## Hints`), `solution.sql`
  (explanatory comments + one query), optional `expected.sql` (performance questions grade against
  the original slow query). Format details are in `CONTRIBUTING.md`.
- Labs (Levels 6+): `kind: script` (answer = migration script run as `run_as` inside a rolled-back
  transaction), `kind: state` (learner changes the DB; `check.sql` inspects it) or `kind: pipeline`
  (answer = load script; `plan:` replays setup, data steps like `batch_1.sql`, and the answer twice
  per batch, then check). Labs have `setup.sql` (idempotent, own schema) and `check.sql`
  returning `(check, ok, detail)`. Lab schemas are listed in the `DROP SCHEMA` in `db/generate.sql`.
  A plan step `parallel:<step>*<n>` (Level 9) runs `<step>.sql` in n concurrent psql sessions
  (`core._run_parallel`); the sequential steps around it run in their own psql sessions.
- Level 8 (`engine: duckdb`): `sqldojo/lake.py` exports Postgres into `lake/raw` via `psql COPY TO
  STDOUT` (no DuckDB extensions; extension downloads are blocked in some sandboxes) and runs
  DuckDB with the repo root as cwd. DuckDB needs `pytz` to return TIMESTAMPTZ values. The
  launcher installs requirements into `.venv` when `core.NeedsDuckDB` is raised. Computing
  per-row date functions on TIMESTAMPTZ is slow in DuckDB; prefer hive partition columns.
- `answers/`: the learner's work and `progress.json`. Never commit test answers or progress here.
- `.github/workflows/`: CI (unit tests + generate at scale 0.05 + selftest + TUI smoke test) and an
  optional daily-question issue workflow (schedule commented out by default; also closes solved issues).
- "Where you left off" lives in `answers/.session.json` (gitignored); `core.resume_question()`.

## Conventions for questions

- Every result must be deterministic: tie-breakers on every `ORDER BY ... LIMIT` and `row_number()`.
- Prompts state filters explicitly (real users = `NOT is_test`, valid orders = not cancelled/returned,
  UTC date ranges `[start, end)`), the expected columns in order, and the rounding.
- Keep results small (aggregate), and check they're non-empty at scale 0.05 (CI) and 1.
- Watch reference-query performance: CTEs referenced several times are materialised with crude
  estimates. Verify with `EXPLAIN ANALYZE` that nothing degenerates into a nested loop.
- Performance targets should leave ~10x headroom over the optimised time measured at scale 1.
