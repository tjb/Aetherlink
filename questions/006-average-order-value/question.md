---
id: 6
title: Average order value by country
level: 1
topics: aggregates of aggregates, HAVING, subqueries
tables: orders, order_items, users
decimals: 2
---
**What was the average order value (AOV) per shipping country for delivered 2025 orders from real users?**

- Only `status = 'delivered'` orders placed in 2025, by real users.
- AOV is the average of **order totals** (`sum(quantity * unit_price)` per order). It is *not* the average line-item value.
- Only include countries (`ship_country`) with **at least 3% of those orders**.

**Expected columns:** `country`, `orders`, `aov` (2 decimals). Order by `aov` descending.

## Hints
- `avg(quantity * unit_price)` straight over `order_items` averages *line items*. Compute one total per order first (a CTE or subquery), then average those.
- `HAVING count(*) >= 0.03 * (SELECT count(*) FROM ...)` compares each group with the overall total. A CTE you can reference twice keeps this tidy.
