---
id: 25
title: Prices as of a date
level: 4
topics: as-of joins, slowly changing dimensions, range predicates
tables: product_prices, products, categories
decimals: 2
---
`products.price` is **today's** price. Prices change over time, and `product_prices` keeps the history: each row applies from `valid_from` (inclusive) until `valid_to` (exclusive), and `valid_to IS NULL` means it is still current.

**What was the average list price per top-level category at the start of each quarter of 2025?** That's 00:00 UTC on Jan 1, Apr 1, Jul 1 and Oct 1.

**Expected columns:** `quarter_start` (date), `top_category`, `products` (number of products with a price at that moment), `avg_price` (2 decimals). 4 × 6 = 24 rows, ordered by `quarter_start`, `top_category`.

## Hints
- This is an *as-of* (point-in-time) join: for each date, find the price row where `valid_from <= d AND (valid_to IS NULL OR valid_to > d)`.
- Using `products.price` gives four identical quarters. That's the most common bug with slowly changing data.
- Another way to write it: `CROSS JOIN LATERAL (SELECT price FROM product_prices WHERE product_id = p.product_id AND valid_from <= d ORDER BY valid_from DESC LIMIT 1)`. It works even when there's no `valid_to` column at all.
