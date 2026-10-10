---
id: 50
title: Partition pruning
level: 8
engine: duckdb
topics: partition pruning, predicate pushdown, row-group statistics, EXPLAIN ANALYZE
tables: lake/silver/events
max_files_read: glob:lake/silver/events/month=2025-12/*.parquet
---
Christmas Eve report: **how many purchases per device on 2025-12-24 (UTC)?** Answer it from your
silver Parquet layer (Q048).

The grader checks the result **and how many files your query opens**. It may only read the files
of the December partition.

**Expected columns:** `device`, `purchases`.

## Hints
- `WHERE occurred_at >= '2025-12-24' AND occurred_at < '2025-12-25'` gives the right answer, but look at `EXPLAIN ANALYZE`: how many files does it read?
- Parquet min/max statistics let DuckDB skip *row groups inside* a file, but the file still has to be opened to read them. Skipping *whole files* takes a filter on the partition column (`month`, from the folder name, with `hive_partitioning = true`).
- Keep the precise `occurred_at` filter too: the partition filter only narrows down the files.
