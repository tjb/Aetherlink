---
id: 29
title: What time do people buy?
level: 4
topics: time zones, AT TIME ZONE, timestamptz, zero-filling
tables: orders, users
---
All timestamps are `timestamptz`, stored as absolute instants and displayed in the session time zone (UTC here). Customers live all over the world.

**For 2025 orders from real users (any status), count orders by hour of day, once in the customer's own local time (`users.timezone`) and once in UTC.**

**Expected columns:** `hour` (0–23), `orders_local`, `orders_utc`. 24 rows (include zero counts), ordered by hour.

## Hints
- `created_at AT TIME ZONE users.timezone` converts a `timestamptz` to a *local* `timestamp` (without time zone) in that zone. The zone can come from a column, and daylight saving time is handled for you.
- `extract(hour FROM ...)` then gives the local hour.
- The UTC histogram is smeared across the day because customers span many time zones. The local one shows the real evening peak.
