---
id: 47
title: Query the landing zone
level: 8
engine: duckdb
topics: DuckDB, querying files, globs, hive partitioning, partition pruning
tables: lake/raw/events/day=*/events_0.csv.gz
max_files_read: glob:lake/raw/events/day=2025-12-*/*.csv.gz
---
Welcome to the lake. `./dojo lake` exported the dataset as files, the way most companies' raw
data lands: **one gzipped CSV per day** under `lake/raw/events/`, in folders named after the
partition:

```
lake/raw/events/day=2025-12-24/events_0.csv.gz
lake/raw/events/day=2025-12-25/events_0.csv.gz
...
```

From now on your queries run in **DuckDB**, an in-process analytical database that queries files
directly. No loading, no server.

**Count December 2025's events by event type and device, straight from the raw files.**

There's a catch: the grader also counts **how many files your query reads**. It may read only
December's 31 files.

**Expected columns:** `event_type`, `device`, `events`.

## Hints
- `SELECT * FROM read_csv('lake/raw/events/*/*.csv.gz') LIMIT 5` reads every file the glob matches. DuckDB detects the CSV dialect, the types and the compression by itself.
- With `hive_partitioning = true`, a folder name like `day=2025-12-24` becomes a column `day` you can filter on. Filters on that column are applied to *folder names*, so the other files are never opened. A filter on `occurred_at` must open every file to look inside.
- `EXPLAIN ANALYZE <your query>` shows "Total Files Read".
