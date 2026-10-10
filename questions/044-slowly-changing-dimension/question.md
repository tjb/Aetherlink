---
id: 44
title: Slowly changing dimension
level: 7
kind: pipeline
plan: setup, snapshot_1, answer, answer, snapshot_2, answer, answer, snapshot_3, answer, answer, check
topics: SCD type 2, history tables, valid_from / valid_to, change detection
tables: crm.customers, crm.dim_customer_history
---
Customers move countries, switch plans and change emails. Finance needs to know **what was true
at any point in time** ("revenue by the customer's country *at the time of the order*"), so
overwriting the old values isn't an option. That's a **type 2 slowly changing dimension**.

Each week the CRM exports a full snapshot into `crm.customers` (`user_id`, `email`, `country`,
`plan`, `snapshot_at`). New customers can appear in any snapshot. Nobody disappears.

Maintain **`crm.dim_customer_history`** (already created, empty):

| column | meaning |
|---|---|
| `customer_sk` | surrogate key (`bigserial`, fill it automatically) |
| `user_id`, `email`, `country`, `plan` | the tracked attributes |
| `valid_from` | the `snapshot_at` where this version first appeared |
| `valid_to` | the `snapshot_at` where it was replaced. **NULL for the current version** |
| `is_current` | true for exactly one row per customer |

Rules: a new customer gets one current row. When any of `email`, `country` or `plan` changed
since the current version, close it (`valid_to`, `is_current = false`) and insert a new current
version. Unchanged customers are untouched. The checker loads three weekly snapshots and runs
your script twice after each.

## Hints
- Two statements, in this order: (1) `UPDATE` the current rows whose attributes differ from the snapshot to close them, then (2) `INSERT` a new current row for every snapshot customer who has no current row any more (changed ones, which you just closed, and brand-new ones).
- Compare with `(d.email, d.country, d.plan) IS DISTINCT FROM (s.email, s.country, s.plan)`.
- To query "as of" a date later: `WHERE valid_from <= t AND (valid_to IS NULL OR valid_to > t)`, the same half-open interval as Q021.
