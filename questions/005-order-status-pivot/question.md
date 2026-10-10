---
id: 5
title: Order status pivot
level: 1
topics: conditional aggregation, FILTER, pivoting
tables: orders
decimals: 1
---
Operations wants one row per device showing how 2025 orders ended up. Include **all orders placed in 2025**, test users too.

**Expected columns:** `device`, `delivered`, `shipped`, `pending`, `returned`, `cancelled` (order counts per status), and `cancel_rate_pct` (cancelled as a percentage of all that device's orders, 1 decimal). One row per device, ordered by device.

## Hints
- Turning row values into columns is called *pivoting*. In plain SQL: one aggregate per output column, each counting only its own rows.
- `count(*) FILTER (WHERE status = 'delivered')` is the Postgres way. `sum(CASE WHEN status = 'delivered' THEN 1 ELSE 0 END)` works everywhere.
