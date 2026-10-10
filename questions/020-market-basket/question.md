---
id: 20
title: Bought together
level: 3
topics: self-joins, market basket analysis, pair counting
tables: order_items, orders, users
---
**Which pairs of different products are most often bought in the same order?**

- Valid 2025 orders (not cancelled/returned) from real users.
- Count each order at most once per pair, even if a product is on two lines.
- Report each pair once, with `product_a < product_b`.

**Expected columns:** `product_a`, `product_b`, `orders_together`. Top 10, ordered by `orders_together` descending, then `product_a`, then `product_b`.

## Hints
- Self-join the order lines on `order_id` with `a.product_id < b.product_id`. The `<` drops self-pairs and the mirrored duplicate `(b, a)`.
- De-duplicate `(order_id, product_id)` *before* the self-join.
- Self-joins grow quadratically with basket size. Look at `EXPLAIN ANALYZE` and the row counts at each step.
