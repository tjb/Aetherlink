---
id: 10
title: Time to second order
level: 2
topics: ROW_NUMBER, LEAD, percentile_cont, interval arithmetic
tables: orders, users
decimals: 1
---
Customer success wants to know whether first-time buyers come back.

**Take every real user whose first-ever order (any status) was placed in 2024. How many placed a second order (any status, any time later)? For those who did, how long did it take?**

- Order a user's orders by `created_at`, breaking ties by `order_id`.
- Days to second order = `(second.created_at - first.created_at)` as **fractional days** (e.g. 2.5 = two and a half days).

**Expected columns:** `first_time_buyers`, `repeat_buyers`, `repeat_rate_pct`, `median_days`, `avg_days`. All decimals to 1 place. One row.

## Hints
- `row_number() OVER (PARTITION BY user_id ORDER BY created_at, order_id)` numbers each user's orders. Or use `lead(created_at) OVER (...)` to put the next order's timestamp on the same row.
- Find the first order *before* filtering by year. A user whose first order was in 2023 must not count just because they also ordered in 2024.
- `extract(epoch FROM some_interval) / 86400` gives fractional days. The median is `percentile_cont(0.5) WITHIN GROUP (ORDER BY x)`.
