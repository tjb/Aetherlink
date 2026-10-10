---
id: 26
title: Latest orders with LATERAL
level: 4
topics: LATERAL joins, top-N per group, correlated subqueries
tables: orders, order_items, users
decimals: 2
---
Account managers look after our 20 most loyal customers.

**For the 20 real users with the most orders (any status, all time; ties go to the smaller `user_id`), list each one's 3 most recent orders and each order's total value.**

- "Most recent" = latest `created_at`; ties go to the larger `order_id`.
- Order total = `sum(quantity * unit_price)` of its items.

**Expected columns:** `user_id`, `order_id`, `created_at`, `order_total` (2 decimals). 60 rows ordered by `user_id`, then `created_at` descending.

## Hints
- `FROM top_users t CROSS JOIN LATERAL (SELECT ... FROM orders o WHERE o.user_id = t.user_id ORDER BY ... LIMIT 3) r` runs the subquery once per outer row and may refer to `t`. That's what `LATERAL` adds.
- Compare with the `row_number()` approach from Q007. Which one reads 90,000 orders and which one reads 60? (`EXPLAIN ANALYZE`, and note the index on `orders(user_id)`.)
