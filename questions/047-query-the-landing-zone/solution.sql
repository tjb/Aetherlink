-- Q047 · Query the landing zone
--
-- A data lake is just files in a directory tree (local disk here, S3/GCS/ADLS in real life),
-- plus engines that query them in place: DuckDB, Spark, Trino, Athena, BigQuery external tables...
--
-- Hive-style partitioning encodes a column in the path (day=2025-12-24). Engines turn it back into
-- a column and, more importantly, prune: a filter on the partition column is evaluated against
-- folder names *before* any file is opened. With 1,096 daily files, filtering on `day` reads 31
-- of them. Filtering on occurred_at opens all 1,096, decompresses them and throws away 97% of
-- the rows. On S3, every file opened is also a request you pay for and wait on.
--
-- Choose partition columns for the filters people actually use (almost always a date), and
-- keep partitions big enough (Q051, Q053): many tiny files are a classic lake performance killer.
SELECT event_type, device, count(*) AS events
FROM read_csv('lake/raw/events/*/*.csv.gz', hive_partitioning = true)
WHERE day >= DATE '2025-12-01' AND day < DATE '2026-01-01'
GROUP BY event_type, device
ORDER BY event_type, device;
