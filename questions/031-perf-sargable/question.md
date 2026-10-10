---
id: 31
title: Make it sargable
level: 5
topics: sargability, B-tree vs BRIN, index-only scans, functions on indexed columns
tables: events
target_ms: 25
target_scaling: linear
---
An ops dashboard counts the last day's events by type:

```sql
SELECT event_type, count(*) AS events
FROM events
WHERE date_trunc('day', occurred_at) = '2025-12-31'
GROUP BY event_type;
```

It reads the entire `events` table to return 6 rows. **Make it return the same result in under 25 ms** (× your dataset scale). You may create indexes. Your answer file must contain only the `SELECT`.

**Expected columns:** `event_type`, `events`.

## Hints
- An index on `occurred_at` can't help `date_trunc('day', occurred_at) = ...`: the indexed column is wrapped in a function. Rewrite the predicate so the bare column is compared with constants.
- "Sargable" = Search ARGument ABLE: the predicate can be answered by an index search.
- Events were written in time order. Look up BRIN indexes, then compare their size with a B-tree: `SELECT pg_size_pretty(pg_relation_size('your_index'))`.
