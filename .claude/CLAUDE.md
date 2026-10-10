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
- `answers/`: the learner's work and `progress.json`. Never commit test answers or progress here.
- `.github/workflows/`: CI (unit tests + generate at scale 0.05 + selftest + TUI smoke test), daily
  question issue, close solved issues.

## Conventions for questions

- Every result must be deterministic: tie-breakers on every `ORDER BY ... LIMIT` and `row_number()`.
- Prompts state filters explicitly (real users = `NOT is_test`, valid orders = not cancelled/returned,
  UTC date ranges `[start, end)`), the expected columns in order, and the rounding.
- Keep results small (aggregate), and check they're non-empty at scale 0.05 (CI) and 1.
- Watch reference-query performance: CTEs referenced several times are materialised with crude
  estimates. Verify with `EXPLAIN ANALYZE` that nothing degenerates into a nested loop.
- Performance targets should leave ~10x headroom over the optimised time measured at scale 1.
