-- Q050 · Partition pruning
--
-- Three levels of skipping, from coarse to fine:
--   1. Partition pruning: filters on hive columns (month=...) are applied to paths. Files in
--      other folders are never opened. ("Total Files Read" in EXPLAIN ANALYZE.)
--   2. Row-group pruning ("zone maps"): each Parquet row group stores min/max per column, so a
--      filter on occurred_at skips row groups that can't match. The file must still be opened
--      to read its footer, which costs a request per file on S3.
--   3. Late materialization: columns not needed for the filter are only decoded for the rows
--      that survive it.
--
-- Engines can't infer that month = strftime(occurred_at, '%Y-%m'). Write the redundant
-- partition filter yourself, or use a table format that records partition transforms (Iceberg's
-- "hidden partitioning" does exactly that, so users can filter on occurred_at alone).
SELECT device, count(*) AS purchases
FROM read_parquet('lake/silver/events/*/*.parquet', hive_partitioning = true)
WHERE month = '2025-12'
  AND occurred_at >= TIMESTAMPTZ '2025-12-24' AND occurred_at < TIMESTAMPTZ '2025-12-25'
  AND event_type = 'purchase'
GROUP BY device
ORDER BY device;
