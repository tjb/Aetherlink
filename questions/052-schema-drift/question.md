---
id: 52
title: Schema drift
level: 8
engine: duckdb
topics: JSON, schema evolution, union_by_name, type coercion, defensive parsing
tables: lake/raw/partner_orders/*.json
decimals: 2
---
Our EU marketplace partner drops one JSON file per month into `lake/raw/partner_orders/`. Their
API changed twice in 2025, and nobody told us:

- **January–June**: `order_id`, `ts`, `total`, `country`
- **July–September**: `total` was renamed **`amount_usd`**, and a new **`channel`** field
  (`web` / `app`) appeared
- **October–December**: `ts` switched to ISO-8601 strings like `2025-10-03T14:05:00Z`, and
  `channel` gained a new value, `marketplace`

Orders from before `channel` existed were all `web` orders.

**For each quarter of 2025 and each channel: the number of orders and the revenue.**

**Expected columns:** `quarter` (date, first day of the quarter), `channel`, `orders`, `revenue`
(2 decimals).

## Hints
- `read_json('lake/raw/partner_orders/*.json')` takes its schema from the first files it samples. `union_by_name = true` reads *all* files' columns and fills the missing ones with NULL.
- Look at what you got: `DESCRIBE SELECT * FROM read_json(..., union_by_name = true)`. What type did `ts` end up with? Casting it with `::TIMESTAMPTZ` handles both timestamp formats.
- `coalesce(amount_usd, total)` and `coalesce(channel, 'web')`.
