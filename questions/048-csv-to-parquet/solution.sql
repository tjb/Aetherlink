-- Q048 · CSV to partitioned Parquet
--
-- Why Parquet wins for analytics:
--   * Columnar: values of one column are stored together, so a query reading 2 of 7 columns
--     reads ~2/7 of the bytes. CSV must parse every byte of every row.
--   * Typed and encoded: integers as integers, dictionary encoding for repetitive strings
--     (device, event_type), run-length encoding, then a general compressor (ZSTD) on top.
--   * Self-describing: the schema and per-row-group min/max statistics live in the footer, so
--     engines can skip data without reading it (Q050, Q051).
-- Compare the sizes: du -sh lake/raw/events lake/silver/events
--
-- Medallion layers: bronze = raw as delivered (CSV, JSON), silver = cleaned/typed/deduplicated,
-- gold = business-level aggregates and marts. Keeping bronze means you can always rebuild silver
-- when you find a bug.
COPY (
  SELECT event_id,
         occurred_at,
         user_id,
         device,
         event_type,
         product_id::INTEGER AS product_id,
         properties::JSON    AS properties,
         strftime(occurred_at, '%Y-%m') AS month
  FROM read_csv('lake/raw/events/*/*.csv.gz', hive_partitioning = true)
) TO 'lake/silver/events' (FORMAT parquet, COMPRESSION zstd, PARTITION_BY (month));

SELECT count(*) AS files FROM glob('lake/silver/events/*/*.parquet');
