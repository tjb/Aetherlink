---
id: 49
title: Row store vs column store
level: 8
engine: duckdb
topics: columnar storage, vectorized execution, OLTP vs OLAP, Parquet
tables: lake/silver/events
target_ms: 300
target_scaling: linear
---
Remember Q032? Monthly active users over the whole events table took **seconds** in Postgres
(at scale 1), and the fix was to precompute it.

**Answer the same question with DuckDB over your Parquet silver layer (from Q048), in under
300 ms** (× your dataset scale), with no precomputation:

> For each month, the number of distinct logged-in users (`user_id` not NULL) with at least one
> event.

**Expected columns:** `month` (text, `YYYY-MM`), `monthly_active_users`. 36 rows.

Then run the same query over the raw CSVs, and compare all three numbers: Postgres, CSV and
Parquet. Why such a difference? The explanation (`Ctrl+O` once solved) goes through it.

## Hints
- `read_parquet('lake/silver/events/*/*.parquet')` and `count(DISTINCT user_id)`. Nothing fancy.
- Computing the month from `occurred_at` for every row of millions costs real time, but the month is already sitting in the folder names. With `hive_partitioning = true` you get it as a column for free.
- If it's slow, check that you're reading Parquet, not CSV.
