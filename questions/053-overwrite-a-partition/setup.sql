-- Lab for Q053: Q4 2025 events as month-partitioned Parquet.
COPY (
  SELECT event_id, occurred_at, user_id, device, event_type, product_id, properties,
         strftime(occurred_at, '%Y-%m') AS month
  FROM read_csv('lake/raw/events/*/*.csv.gz', hive_partitioning = true)
  WHERE day >= DATE '2025-10-01'
) TO 'lake/lab/events_q4' (FORMAT parquet, COMPRESSION zstd, PARTITION_BY (month));
