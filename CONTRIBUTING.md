# Adding questions

A question is a directory under `questions/` named `NNN-short-slug/`:

```
questions/034-my-question/
├── question.md     the problem (front matter + markdown + hints)
├── solution.sql    the reference solution, with an explanation in comments
└── expected.sql    optional: grade against this query instead of solution.sql
```

## `question.md`

```markdown
---
id: 34
title: Short title (fits the sidebar, under ~32 characters)
level: 3
topics: comma, separated, concepts
tables: orders, users
decimals: 2            # numbers are compared after rounding to this many places (default 2)
ordered: false         # true only if row order is part of the answer
target_ms: 50          # performance questions only
target_scaling: linear # optional: the target is multiplied by the dataset scale
---
The problem statement. Say exactly what to count, which filters apply (real users? valid orders?
which dates?), how to break ties, and how to round.

**Expected columns:** `a`, `b`, `c` (2 decimals). Ordered by `a`.

## Hints
- From a gentle nudge...
- ...to the key idea...
- ...to the trick that cracks it.
```

## `solution.sql`

The first line must be `-- Qnnn · <title>`. Then a comment block that *teaches*: the approach, the
trap, alternatives, what the planner does. Then **one** query.

Make results deterministic: every `ORDER BY ... LIMIT` needs a tie-breaker, and so does every
`row_number()`. Prefer small aggregated results (under ~1,000 rows), which also make better feedback.

## Performance questions

Put the original slow (but correct) query in `expected.sql`. It's what grading compares against,
so it must finish in reasonable time *without* any extra indexes. `solution.sql` lists the setup
(`CREATE INDEX ...`) in comments, followed by the fast query.

## Labs (`kind: script` / `kind: state`)

Labs are graded by inspecting the database instead of comparing a result:

```
questions/035-my-lab/
├── question.md     front matter adds `kind: script` (and `run_as: some_role`) or `kind: state`
├── setup.sql       idempotent: (re)creates the lab's objects in schema `lab`, plus any roles
├── check.sql       returns rows (check text, ok boolean, detail text). All ok = solved
└── solution.sql    a script that passes the checks, with the explanation in comments
```

- **script**: the answer file is a script. Each check runs `setup.sql`, then `BEGIN; SET LOCAL ROLE
  <run_as>; <your script>; RESET ROLE; <check.sql>; ROLLBACK;`. Transaction control and role
  switching are refused in the script.
- **pipeline**: the answer is a load script. Front matter `plan:` lists the steps, e.g.
  `setup, batch_1, answer, answer, batch_2, answer, answer, check`. `setup` runs `setup.sql`,
  `answer` runs the learner's script, any other name runs `<name>.sql` from the question
  directory (landing new data), and `check` must come last. Run `answer` twice in a row to
  enforce idempotency. Give each pipeline lab its own schema and drop it in `setup.sql`, so
  helper tables the learner creates can't survive into the next run (and add the schema to the
  `DROP SCHEMA` list in `db/generate.sql`).
  A step written `parallel:worker*4` runs `worker.sql` in 4 concurrent sessions (psql variable
  `:worker` = 1..4; use `set_config` to pass it into a `DO` block, and `COMMIT` inside the loop
  so the sessions really interleave). Any session failing (a deadlock, a unique violation)
  fails the check. Make the reference solution deterministic under concurrency, and check that
  the usual wrong answers fail (see Q057, Q058).
- **state**: the learner changes the database however they like. `check.sql` runs on the current
  state and may use its own `BEGIN ... ROLLBACK` to try things (see Q039). `setup.sql` runs when
  the lab is first opened and on *Reset this lab*.
- `check.sql` must return a single result set. Other statements in it must not print anything.
- A query question can also have a `setup.sql` (for example to create roles, see Q038).
- `./dojo selftest` checks that the solution passes *and* that doing nothing fails.

## DuckDB questions (Level 8)

`engine: duckdb` runs the question in DuckDB with the repository root as the working directory,
over the files in `lake/`. Query questions work as usual (`expected.sql` should read
`lake/raw/`, which always exists). Extras:

- `max_files_read: 31` or `max_files_read: glob:lake/silver/events/month=2025-12/*.parquet`:
  after the result is right, the grader runs `EXPLAIN ANALYZE` and fails answers that open more
  files ("Total Files Read").
- DuckDB labs are `kind: state` with a DuckDB `check.sql` (same `(check, ok, detail)` contract).
  `lake_paths:` lists the files/folders the lab owns, deleted on reset. `setup.sql` (DuckDB) is
  optional. `freeze_mtimes:` stamps the setup's files with 2026-01-01, so the check can detect
  rewrites (`read_blob(...).last_modified`).

## Check your work

```bash
./dojo selftest --only 34          # runs the reference against your local data
python3 -m unittest discover -s tests
```

CI runs both at scale 0.05 on every push, so make sure the question still returns rows on a
small dataset.
