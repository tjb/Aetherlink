---
id: 23
title: Delivery time percentiles
level: 3
topics: percentile_cont, ordered-set aggregates, FILTER, dirty data
tables: orders
decimals: 1
---
**How fast does each carrier deliver? Report the median, p90 and p99 delivery times for orders shipped in 2025.**

- Delivery time = `delivered_at - shipped_at`, in hours.
- Consider all orders (any status, any user) with `shipped_at` in 2025 and a non-NULL `delivered_at`.
- A faulty scanner recorded some deliveries *before* they shipped. Exclude those from the percentiles and the delivery count, but report how many there were.
- Use continuous percentiles (interpolated, like `percentile_cont`).

**Expected columns:** `carrier`, `deliveries`, `p50_hours`, `p90_hours`, `p99_hours` (1 decimal), `bad_records`. Ordered by `p90_hours` descending.

## Hints
- `percentile_cont(0.9) WITHIN GROUP (ORDER BY hours)` is an *ordered-set aggregate*. Use it with `GROUP BY` like any other aggregate.
- Aggregates accept `FILTER (WHERE ...)`, ordered-set ones included. So one `GROUP BY carrier` can compute clean percentiles and count the bad rows.
- `extract(epoch FROM interval) / 3600` = hours. `percentile_cont` returns double precision, so cast to `numeric` before `round(x, 1)`.
