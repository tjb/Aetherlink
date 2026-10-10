---
id: 8
title: Running total for December
level: 2
topics: window functions, running totals, SUM OVER, window frames
tables: orders, order_items, users
decimals: 1
---
December is the big month. Finance wants to watch it accumulate.

**For each day of December 2025: the day's revenue, the running total since December 1st, and that running total as a percentage of December's full revenue.**

Revenue = valid orders (not cancelled/returned) from real users, `sum(quantity * unit_price)`. A "day" is the UTC date of `created_at`.

**Expected columns:** `day` (date), `revenue`, `running_revenue`, `pct_of_month` (1 decimal; reaches `100.0` on Dec 31). 31 rows ordered by day.

## Hints
- Aggregate to one row per day first, then apply window functions to those daily rows.
- `sum(revenue) OVER (ORDER BY day)` is a running total. `sum(revenue) OVER ()` is the grand total, repeated on every row.
- With `ORDER BY`, the default window frame is `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`. With duplicate `ORDER BY` values that includes the *peers* of the current row, which surprises people. `ROWS` frames don't do that.
