---
id: 33
title: Events before purchase
level: 5
topics: correlated subqueries, nested loops vs hash joins, indexes
tables: orders, users, events
decimals: 2
target_ms: 1000
target_scaling: linear
---
Product wants to know how much browsing happens before a purchase: **for each 2025 order from a real user, count that user's events in the 24 hours before the order was placed, then average by device.**

An analyst wrote this. It's correct, but **it never finishes** (`./dojo run` gives up after 5 minutes):

```sql
SELECT o.device,
       count(*) AS orders,
       round(avg((SELECT count(*)
                  FROM events e
                  WHERE e.user_id = o.user_id
                    AND e.occurred_at >= o.created_at - interval '24 hours'
                    AND e.occurred_at <  o.created_at)), 2) AS avg_events_before
FROM orders o
JOIN users u ON u.user_id = o.user_id
WHERE NOT u.is_test
  AND o.created_at >= '2025-01-01' AND o.created_at < '2026-01-01'
GROUP BY o.device
ORDER BY o.device;
```

**Make it return the same result in under 1 second** (× your dataset scale). You may rewrite the query, create indexes, or both. Then try the *other* fix too and compare.

**Expected columns:** `device`, `orders`, `avg_events_before` (2 decimals).

## Hints
- `./dojo explain 33 --no-analyze` shows the plan without running it. The subquery appears as a `SubPlan` executed once per order. What does each execution do?
- Fix 1: give each execution an index to use, so it costs microseconds instead of a full scan.
- Fix 2: rewrite as a `LEFT JOIN` on `user_id` with the time window in the join condition, then `GROUP BY` order. The planner can then hash-join once instead of looping. Watch out: orders with zero events must still count as 0.
