---
id: 40
title: Bulk load with COPY
level: 7
kind: pipeline
plan: setup, answer, answer, check
topics: COPY, staging tables, type casting, time zones, deduplication, idempotent loads
tables: partner.orders
---
Our European marketplace partner sends a nightly CSV export of the orders they took for us. It
has landed on the database server at **`/tmp/dojo_partner_orders.csv`**:

```
Order ID,Order Date,Customer Email,Country,Units,Total (USD),Status,Notes
91234,24/12/2025 18:05,Maria.Garcia123@Gmail.Com ,DE,3,"1,234.50", Delivered ,"Gift wrap, please"
```

(Peek at it: `SELECT pg_read_file('/tmp/dojo_partner_orders.csv', 0, 2000);`)

**Write a load script that brings it into the empty table `partner.orders`** (it already exists,
look at `\d partner.orders`):

- `ordered_at`: the export uses **day/month/year** and **Berlin local time** (`Europe/Berlin`).
  Store the correct instant.
- `customer_email`: lower case, no surrounding whitespace.
- `total`: a number (the export adds thousands separators).
- `status`: lower case, trimmed.
- Empty fields become `NULL`, not empty strings.
- The partner's system sometimes exports an order twice. Load each order once.
- **Idempotent**: the checker runs your script twice in a row, and the result must be the same.

## Hints
- `COPY table FROM '/path/on/server' WITH (FORMAT csv, HEADER true)` is the fastest way to load a file. It reads the file on the *database server*. (`\copy` in psql reads it on *your* machine instead.)
- Don't COPY straight into the typed table: one bad value aborts the whole load. COPY into a staging table of `text` columns (a temp table is perfect), then `INSERT ... SELECT` with your casts and cleanup.
- Dates: `to_timestamp(s, 'DD/MM/YYYY HH24:MI')` parses the format, `::timestamp AT TIME ZONE 'Europe/Berlin'` says "this was Berlin wall-clock time". Duplicates: `DISTINCT ON (order_id)`. Idempotency: `TRUNCATE` first, or `INSERT ... ON CONFLICT (order_id) DO UPDATE`.
