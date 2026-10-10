---
id: 27
title: Tracking loss (JSONB)
level: 4
topics: JSONB operators, anti-joins, reconciliation, duplicates
tables: orders, events
decimals: 2
---
Every order should have a matching `purchase` event whose `properties` look like `{"order_id": 12345}`. Ad blockers and flaky phones lose some of them, and analytics wants to know how many.

**For orders placed in 2025 (any status, all users), by `orders.device`: how many orders were there, how many have no matching purchase event, and what percentage is that?**

**Expected columns:** `device`, `orders`, `orders_missing_event`, `pct_missing` (2 decimals). Ordered by device.

Careful: the event pipeline delivers some events **twice**.

## Hints
- `properties ->> 'order_id'` extracts a JSON field as text, so cast it: `(properties ->> 'order_id')::bigint`. `->` returns jsonb instead.
- If you `LEFT JOIN` orders to purchase events, duplicated events duplicate orders and inflate the count. Use `NOT EXISTS`, or join to a `DISTINCT` set of tracked order ids.
- A correlated `NOT EXISTS` *inside an aggregate's FILTER* runs once per order and can't become an anti-join. Pre-compute the set of tracked ids instead.
