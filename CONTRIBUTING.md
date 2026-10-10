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

## Check your work

```bash
./dojo selftest --only 34          # runs the reference against your local data
python3 -m unittest discover -s tests
```

CI runs both at scale 0.05 on every push, so make sure the question still returns rows on a
small dataset.
