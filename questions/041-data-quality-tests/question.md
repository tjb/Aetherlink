---
id: 41
title: Data quality tests
level: 7
topics: data tests, NOT NULL, uniqueness, referential integrity, accepted values, dbt-style assertions
tables: dq.orders_snapshot, users
---
Before the nightly models run, the pipeline must prove its input is sane. `dq.orders_snapshot` is
an extract of Q4 2025 orders from the source system. It has **no constraints at all**, and
something upstream went wrong.

Write **one query** that runs seven data tests and reports how many rows fail each one (dbt-style:
a test passes when it finds 0 failing rows):

| test | a row fails when |
|---|---|
| `order_id_not_null` | `order_id` is NULL |
| `order_id_unique` | its (non-NULL) `order_id` appears on more than one row. Count *every* such row |
| `user_id_references_users` | `user_id` is not NULL and doesn't exist in `users` |
| `status_accepted_values` | `status` is NULL or not one of `pending`, `shipped`, `delivered`, `returned`, `cancelled` |
| `amount_between_0_and_50000` | `amount` is NULL, below 0 or above 50,000 |
| `shipped_not_before_created` | `shipped_at` is earlier than `created_at` |
| `created_not_in_future` | `created_at` is on or after `2026-01-01` (the extract ran then) |

**Expected columns:** `test`, `failing_rows`. Seven rows, one per test, including tests with 0 failures.

## Hints
- One SELECT per test, glued together with `UNION ALL`, is exactly how dbt compiles its tests.
- Uniqueness: `GROUP BY order_id HAVING count(*) > 1` finds the duplicated *values*. You need the number of *rows* carrying them (`sum(count)` or a window `count(*) OVER (PARTITION BY order_id)`).
- `status NOT IN (...)` is NULL, not true, when `status` is NULL (Q003 again). Handle NULL explicitly.
