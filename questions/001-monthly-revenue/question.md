---
id: 1
title: Monthly revenue
level: 1
topics: GROUP BY, joins, date_trunc, join fan-out
tables: orders, order_items, users
decimals: 2
---
Finance wants a simple table: **for each month of 2025, how many orders did we take and how much revenue did they bring in?**

Use the standard definitions:

- Only orders from **real users** (`users.is_test = false`).
- Only **valid orders**: `status` is not `'cancelled'` and not `'returned'`.
- An order's value is `sum(quantity * unit_price)` over its `order_items`.
- "2025" means `created_at` in `[2025-01-01, 2026-01-01)` (the database runs in UTC).

**Expected columns:** `month` (date, first day of the month), `orders`, `revenue` (2 decimals). 12 rows, ordered by month.

## Hints
- `date_trunc('month', created_at)::date` turns a timestamp into the first day of its month.
- Joining `orders` to `order_items` gives you one row *per item*, so `count(*)` after the join counts items, not orders. Use `count(DISTINCT o.order_id)` or total up the items per order first.
- Prefer `created_at >= '2025-01-01' AND created_at < '2026-01-01'` over `extract(year FROM created_at) = 2025`. Same answer, but only the first form can use an index (this comes back in Level 5).
