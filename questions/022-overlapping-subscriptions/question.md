---
id: 22
title: Overlapping subscriptions
level: 3
topics: interval overlap, self-joins, range types, data quality
tables: subscriptions
decimals: 1
---
A billing bug gave some users **two subscriptions at the same time**. Find them.

**Return every pair of subscriptions belonging to the same user whose periods overlap.**

- Periods are half-open `[started_at, ended_at)`. `ended_at IS NULL` means still running.
- Touching is not overlapping: one ending exactly when the other starts is fine.
- `overlap_days`: the length of the overlap in fractional days. For overlaps still running, measure up to `2026-01-01 00:00 UTC` (the end of the dataset).

**Expected columns:** `user_id`, `subscription_a`, `subscription_b` (with `subscription_a < subscription_b`), `overlap_days` (1 decimal). Ordered by `user_id`, `subscription_a`, `subscription_b`.

## Hints
- Two intervals `[s1, e1)` and `[s2, e2)` overlap exactly when `s1 < e2 AND s2 < e1`. Draw it on paper once; you'll use it forever.
- Replace a NULL end with `'infinity'` (a real timestamp value in Postgres) or `'2026-01-01'`.
- Postgres range types do this natively: `tstzrange(started_at, ended_at) && tstzrange(...)`, and `*` gives the intersection.
