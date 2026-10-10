-- Q049 · Row store vs column store
--
-- Same data, same question, wildly different times. Why:
--
--  * Storage layout. Postgres stores rows: to read user_id and occurred_at it reads every 8 KB
--    page of the table, all columns included (plus tuple headers, MVCC fields, TOAST'd jsonb).
--    Parquet stores columns: this query reads 2 of 8 columns, already compressed (dictionary +
--    run-length + ZSTD), so it reads a small fraction of the bytes.
--  * Execution. Postgres processes one tuple at a time through a tree of nodes, a design made
--    for OLTP: many small queries, each touching a few rows by index. DuckDB is vectorized: each
--    operator works on batches of ~2,048 values in tight loops that CPUs (and SIMD) love, and
--    it uses all cores by default.
--  * Trade-offs. Columnar engines are bad at what Postgres is great at: updating single rows,
--    many concurrent writers, point lookups by key, transactions. Hence the usual
--    architecture: Postgres (OLTP) for the app, a columnar store (DuckDB, ClickHouse, BigQuery,
--    Snowflake, Parquet on S3...) for analytics, and ELT (Level 7) between them.
--
-- CSV sits at the bottom: text parsing of every byte, no types, no statistics.
--
-- And one more lesson hiding in this query: computing date_trunc('month', occurred_at) on every
-- row is expensive (time-zone-aware calendar math, millions of times), and it can cost more than
-- reading the data. The month is already stored in the partition path, so grouping by the hive
-- column is nearly free. Precompute what everyone groups by, once, at write time.
SELECT month,
       count(DISTINCT user_id) AS monthly_active_users
FROM read_parquet('lake/silver/events/*/*.parquet', hive_partitioning = true)
WHERE user_id IS NOT NULL
GROUP BY month
ORDER BY month;
