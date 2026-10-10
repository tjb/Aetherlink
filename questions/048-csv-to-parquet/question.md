---
id: 48
title: CSV to partitioned Parquet
level: 8
kind: state
engine: duckdb
lake_paths: lake/silver/events
topics: Parquet, columnar storage, compression, hive partitioning, bronze/silver/gold
tables: lake/raw/events, lake/silver/events
---
The raw CSVs are the "bronze" layer: exactly what arrived, cheap to keep, slow to query. Build
the **silver** layer: the same events, typed and stored in a format made for analytics.

**Write all events to `lake/silver/events/` as Parquet:**

- partitioned by month, in folders like `lake/silver/events/month=2025-12/` (`month` = `YYYY-MM`
  of `occurred_at`, UTC);
- **ZSTD**-compressed;
- with proper types: `occurred_at` must be a `TIMESTAMP WITH TIME ZONE`, ids integers;
- every event exactly once.

Run your statements from the editor (`Ctrl+R` executes everything in DuckDB), then check. Later
questions (49, 50) query what you build here.

## Hints
- `COPY (SELECT ...) TO 'lake/silver/events' (FORMAT parquet, COMPRESSION zstd, PARTITION_BY (month))` writes one folder per distinct `month` value.
- `strftime(occurred_at, '%Y-%m') AS month` makes the partition value. By default the partition column is stored in the folder name, not inside the files.
- Inspect your work: `SELECT * FROM parquet_metadata('lake/silver/events/*/*.parquet')` (row groups, compression, min/max statistics) and `DESCRIBE SELECT * FROM read_parquet('lake/silver/events/*/*.parquet', hive_partitioning = true)`. Compare `du -sh lake/raw/events lake/silver/events` in a shell.
