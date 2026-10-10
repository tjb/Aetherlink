---
id: 46
title: Partitioning and retention
level: 7
kind: state
topics: declarative partitioning, partition pruning, retention, DROP vs DELETE
tables: archive.events
---
The events table grows forever, but the product team only needs the last quarter online. Deleting
old rows with `DELETE` is slow, writes WAL for every row and leaves bloat (Q036). The production
pattern is to **partition by time and drop whole partitions**.

In the empty schema `archive`:

1. Create **`archive.events`** with the same columns as `public.events`, **range-partitioned on
   `occurred_at`**, with one partition per calendar month of 2025 named `archive.events_2025_01`
   ... `archive.events_2025_12` (month boundaries at 00:00 UTC).
2. Load **all 2025 events** into it.
3. Apply the retention policy, "keep only Q4 2025", by **dropping** the January–September
   partitions.

Then check. The checker verifies the structure, the data, and that a query for a single day only
reads one partition. That's *partition pruning*, and it's what makes partitioned tables fast.

## Hints
- `CREATE TABLE archive.events (LIKE public.events) PARTITION BY RANGE (occurred_at);` then for each month `CREATE TABLE archive.events_2025_01 PARTITION OF archive.events FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');`. The upper bound is exclusive, as always.
- Twelve near-identical statements: write them by hand, or generate them with `SELECT format(...) FROM generate_series(...)` and run them with psql's `\gexec` (or a `DO` block).
- `INSERT INTO archive.events SELECT * FROM public.events WHERE ...` routes each row to its partition. Afterwards `EXPLAIN SELECT count(*) FROM archive.events WHERE occurred_at >= '2025-12-24' AND occurred_at < '2025-12-25'` should mention only one partition.
