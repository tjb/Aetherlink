---
id: 24
title: Subtotals with CUBE
level: 3
topics: GROUPING SETS, ROLLUP, CUBE, GROUPING()
tables: order_items, orders, users, products, categories
decimals: 2
---
**One query, one table: 2025 revenue by top-level category and order device, with subtotals for each category, for each device, and a grand total.**

- Revenue: valid 2025 orders (not cancelled/returned) from real users.
- Use the literal `'All'` where a dimension is rolled up. The grand total row is `('All', 'All', ...)`.
- Find the top-level category by walking up two levels from the product's leaf category (as in Q007).

**Expected columns:** `top_category`, `device`, `revenue` (2 decimals). 6 categories × 3 devices + 6 + 3 + 1 = 28 rows.

## Hints
- `GROUP BY CUBE (a, b)` = `GROUPING SETS ((a, b), (a), (b), ())`. `ROLLUP (a, b)` = `GROUPING SETS ((a, b), (a), ())`.
- In subtotal rows the rolled-up column is NULL. `GROUPING(col)` returns 1 when a NULL comes from rollup, which tells it apart from a real NULL in the data.
