WITH files AS (
  SELECT file FROM glob('lake/silver/events/*/*.parquet')
), stamp AS (
  SELECT events FROM read_json('lake/.built.json')
), raw_months AS (
  SELECT count(DISTINCT strftime(day, '%Y-%m')) AS n
  FROM read_csv('lake/raw/events/*/*.csv.gz', hive_partitioning = true, columns = {'event_id': 'BIGINT'})
), silver AS (
  SELECT * FROM read_parquet('lake/silver/events/*/*.parquet', hive_partitioning = true)
), types AS (
  SELECT column_name, column_type
  FROM (DESCRIBE SELECT * FROM read_parquet('lake/silver/events/*/*.parquet', hive_partitioning = true))
), meta AS (
  SELECT DISTINCT compression FROM parquet_metadata('lake/silver/events/*/*.parquet')
)
SELECT 'Parquet files exist under lake/silver/events/month=YYYY-MM/' AS check,
       (SELECT count(*) FROM files) > 0 AND (SELECT bool_and(file LIKE '%/month=____-__/%') FROM files) AS ok,
       format('{} files', (SELECT count(*) FROM files)) AS detail
UNION ALL
SELECT 'one partition per month',
       (SELECT count(DISTINCT month) FROM silver) = (SELECT n FROM raw_months),
       format('{} partitions, {} months in the data', (SELECT count(DISTINCT month) FROM silver), (SELECT n FROM raw_months))
UNION ALL
SELECT 'every event exactly once',
       (SELECT count(*) FROM silver) = (SELECT events FROM stamp)
         AND (SELECT count(DISTINCT event_id) FROM silver) = (SELECT count(*) FROM silver),
       format('{} rows, {} distinct event_ids, {} events in the lake',
              (SELECT count(*) FROM silver), (SELECT count(DISTINCT event_id) FROM silver), (SELECT events FROM stamp))
UNION ALL
SELECT 'every row sits in the partition of its month (UTC)',
       (SELECT count(*) FROM silver WHERE strftime(occurred_at, '%Y-%m') <> month) = 0,
       format('{} misplaced rows', (SELECT count(*) FROM silver WHERE strftime(occurred_at, '%Y-%m') <> month))
UNION ALL
SELECT 'occurred_at is TIMESTAMP WITH TIME ZONE, event_id is BIGINT',
       (SELECT column_type FROM types WHERE column_name = 'occurred_at') = 'TIMESTAMP WITH TIME ZONE'
         AND (SELECT column_type FROM types WHERE column_name = 'event_id') = 'BIGINT',
       (SELECT string_agg(column_name || ' ' || column_type, ', ') FROM types
        WHERE column_name IN ('event_id', 'occurred_at'))
UNION ALL
SELECT 'compressed with ZSTD',
       (SELECT bool_and(compression = 'ZSTD') FROM meta),
       (SELECT string_agg(compression, ', ') FROM meta)
