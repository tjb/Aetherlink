-- Q051 · Sort for zone maps
--
-- Row-group statistics only help if values are clustered. Unsorted, every row group spans
-- nearly every user_id (min ~1, max ~N), so nothing can be skipped. Sorted, each row group
-- covers a narrow slice and a point lookup touches one or two of them.
--
-- The same idea goes by other names:
--   * "clustering" (BigQuery, Snowflake): the engine keeps data roughly sorted by chosen keys;
--   * Z-ordering / Hilbert curves (Delta, Iceberg): sort by several columns at once, trading
--     some precision on each for decent skipping on all;
--   * BRIN indexes in Postgres (Q031): min/max per block range, same trick inside a row store.
--
-- You can only sort by one thing. Partition by the coarse filter everybody uses (date), sort
-- inside partitions by the next most selective one (user, customer, tenant). Row-group size is
-- a trade-off: smaller = finer skipping but more metadata and worse compression. 100k-1M rows
-- is typical.
COPY (
  SELECT event_id, occurred_at, user_id, device, event_type, product_id, properties
  FROM read_csv('lake/raw/events/*/*.csv.gz', hive_partitioning = true)
  ORDER BY user_id NULLS LAST, occurred_at
) TO 'lake/gold/events_by_user.parquet' (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE 100000);

SELECT row_group_id, row_group_num_rows, stats_min_value, stats_max_value
FROM parquet_metadata('lake/gold/events_by_user.parquet')
WHERE path_in_schema = 'user_id'
ORDER BY row_group_id
LIMIT 5;
