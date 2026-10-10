---
id: 53
title: Overwrite one partition
level: 8
kind: state
engine: duckdb
lake_paths: lake/lab/events_q4, lake/lab/staging_2025-11.parquet
freeze_mtimes: lake/lab/events_q4
topics: partition overwrite, immutable files, staging, idempotent rewrites, table formats
tables: lake/lab/events_q4, lake/raw/corrections/bot_events_2025-11.csv
---
The lab gives you Q4 2025 events as Parquet, partitioned by month in `lake/lab/events_q4/`
(`month=2025-10`, `month=2025-11`, `month=2025-12`).

Data science found that **QA bots** polluted November. The list of their event ids arrived as
`lake/raw/corrections/bot_events_2025-11.csv`. **Remove those events from the November partition.**

The rules of the lake:

- files are **immutable**: there's no `DELETE` on a Parquet file, you rewrite it;
- rewrite **only** the November partition. The October and December files must not be touched
  (consumers cache them, and on S3 rewriting costs money);
- November must end up with every non-bot event, exactly once.

Make the change from the editor (`Ctrl+R` runs your statements in DuckDB), then check.
*Reset this lab* puts the original files back.

## Hints
- `COPY ... TO 'lake/lab/events_q4' (FORMAT parquet, PARTITION_BY (month), OVERWRITE)` would delete the whole folder, October and December included. Aim the write at the November folder itself: `COPY ... TO 'lake/lab/events_q4/month=2025-11' (FORMAT parquet, PER_THREAD_OUTPUT true, OVERWRITE true)` replaces just that folder's files.
- Never overwrite the files you're reading from in the same statement. Write the corrected rows to a staging file first, then from staging into the partition.
- `event_id NOT IN (SELECT event_id FROM read_csv('lake/raw/corrections/bot_events_2025-11.csv'))`. Is `NOT IN` safe here? (Q003.)
