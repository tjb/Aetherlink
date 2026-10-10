---
id: 51
title: Sort for zone maps
level: 8
kind: state
engine: duckdb
lake_paths: lake/gold/events_by_user.parquet
topics: row groups, min/max statistics, zone maps, clustering, file layout
tables: lake/raw/events, lake/gold/events_by_user.parquet
---
The support team constantly looks up **one user's full history**. In your silver layer every
month's file contains every user, so each lookup scans everything.

Parquet splits a file into **row groups** and stores the **min and max** of every column per row
group. If the data is *sorted* by `user_id`, each row group covers a narrow range of users, and a
lookup can skip every row group whose range doesn't contain the user. That's a *zone map*.

**Write every event to a single file, `lake/gold/events_by_user.parquet`, sorted by `user_id`
(NULLs last), with row groups of 100,000 rows.**

The checker reads the file's metadata: the row groups must have non-overlapping `user_id`
ranges, and looking up any one user must need at most two row groups.

## Hints
- `COPY (SELECT ... ORDER BY user_id NULLS LAST) TO 'lake/gold/events_by_user.parquet' (FORMAT parquet, ROW_GROUP_SIZE 100000)`.
- Look at the result: `SELECT row_group_id, row_group_num_rows, stats_min_value, stats_max_value FROM parquet_metadata('lake/gold/events_by_user.parquet') WHERE path_in_schema = 'user_id'`. Now do the same on an unsorted file.
- Time a lookup (`WHERE user_id = 4242`) against this file and against `lake/silver/events`, and look at both with `EXPLAIN ANALYZE`.
