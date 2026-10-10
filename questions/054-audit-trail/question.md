---
id: 54
title: An audit trail
level: 9
kind: pipeline
plan: setup, answer, answer, workload, check
topics: triggers, OLD/NEW, WHEN clauses, to_jsonb, TRUNCATE triggers, audit logging
tables: audit.products, audit.product_log
---
Compliance wants a record of **every change** to the catalogue, however it was made: by the app,
by a migration, or by someone in `psql`. You decide to have the database write it.

Write triggers on **`audit.products`** that fill **`audit.product_log`** (it already exists; its
`log_id`, `tx_id`, `changed_at` and `changed_by` fill themselves):

| `op` | `product_id` | `old_row` | `new_row` |
|---|---|---|---|
| `INSERT` | the product | NULL | the new row as `jsonb` |
| `UPDATE` | the product | the row before | the row after |
| `DELETE` | the product | the row before | NULL |
| `TRUNCATE` | NULL | NULL | NULL |

Two rules keep the log useful:
- An `UPDATE` that **changes nothing** isn't logged. (ORMs love saving unchanged rows.)
- `view_count` is bumped on every page view. An update that **only** changes `view_count` isn't
  logged. An update that changes it *and* something else is.

The checker runs your script **twice**, then replays a day of changes (inserts, updates, a
rolled-back transaction, deletes, and a `TRUNCATE`) and inspects the log. Every change must be
logged exactly once.

## Hints
- A trigger function `RETURNS trigger`; inside it `TG_OP` is `'INSERT'`, `'UPDATE'`, `'DELETE'` or `'TRUNCATE'`, and `to_jsonb(OLD)` / `to_jsonb(NEW)` turn rows into JSON. `CREATE OR REPLACE TRIGGER` makes the script safe to rerun.
- Filter in the trigger definition: `CREATE TRIGGER ... AFTER UPDATE ON ... FOR EACH ROW WHEN (...)`. Compare `to_jsonb(OLD) - 'view_count'` with the same for `NEW`, using `IS DISTINCT FROM`.
- `TRUNCATE` doesn't fire `DELETE` triggers. It needs its own `AFTER TRUNCATE ... FOR EACH STATEMENT` trigger, which can't see the rows (there are no `OLD` values).
