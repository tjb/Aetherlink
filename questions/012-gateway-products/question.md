---
id: 12
title: Gateway products
level: 2
topics: DISTINCT ON, first row per group, COUNT DISTINCT
tables: orders, order_items, users, products
---
Which products bring new customers in?

**Look at each real user's first order: earliest `created_at`, ties broken by the smaller `order_id`, any status. Which 10 products appear in the most first orders?**

Count each user once per product, even if the product is on two lines of the same order.

**Expected columns:** `product_id`, `product_name`, `first_order_users`. 10 rows, ordered by `first_order_users` descending, then `product_id`.

## Hints
- "First row per group" is everywhere. Postgres has a shortcut: `SELECT DISTINCT ON (user_id) ... ORDER BY user_id, created_at, order_id` keeps the first row of each `user_id`.
- The portable version: `row_number() OVER (PARTITION BY user_id ORDER BY created_at, order_id) = 1`.
- The tie-breaker on `product_id` decides which products make the cut at #10, so it matters.
