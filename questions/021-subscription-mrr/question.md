---
id: 21
title: Subscription MRR
level: 3
topics: date spines, interval logic, point-in-time snapshots, FILTER
tables: subscriptions
decimals: 2
---
Larkspur Plus is a paid membership (`subscriptions`). Each row is one subscription period `[started_at, ended_at)`, and `ended_at IS NULL` means still active.

**For each month of 2025, report the subscriptions active at the end of that month, the MRR (monthly recurring revenue) they represent, and how many subscriptions started and ended during the month.**

- "End of month" is the instant the next month begins (January's snapshot is `2025-02-01 00:00 UTC`). A subscription is active at instant `T` if `started_at <= T` and (`ended_at IS NULL` or `ended_at > T`).
- MRR = `sum(monthly_price)` of the active subscriptions (annual plans are already normalised per month).
- Started/ended during the month: `started_at` / `ended_at` within `[month start, next month start)`.
- Count subscriptions, not users.

**Expected columns:** `month` (date, first day), `active_subscriptions`, `mrr`, `new_subscriptions`, `ended_subscriptions`. 12 rows ordered by month.

## Hints
- Build a *date spine* with `generate_series(timestamptz '2025-01-01', '2025-12-01', interval '1 month')` and join it to `subscriptions`.
- With only 12 months, `CROSS JOIN` plus `count(*) FILTER (WHERE ...)` for each measure is simple and fast.
- NULL `ended_at` again! `ended_at > T` is NULL for open subscriptions.
