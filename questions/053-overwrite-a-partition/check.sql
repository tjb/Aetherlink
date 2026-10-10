WITH lab AS (
  SELECT * FROM read_parquet('lake/lab/events_q4/*/*.parquet', hive_partitioning = true)
), raw AS (
  SELECT event_id, strftime(occurred_at, '%Y-%m') AS month
  FROM read_csv('lake/raw/events/*/*.csv.gz', hive_partitioning = true)
  WHERE day >= DATE '2025-10-01'
), bots AS (
  SELECT event_id FROM read_csv('lake/raw/corrections/bot_events_2025-11.csv')
), expected_nov AS (
  SELECT event_id FROM raw WHERE month = '2025-11' AND event_id NOT IN (SELECT event_id FROM bots)
), files AS (  -- the lab stamps its files 2026-01-01; anything newer was rewritten
  SELECT filename, last_modified FROM read_blob('lake/lab/events_q4/*/*.parquet')
)
SELECT 'November has no bot events left' AS check,
       (SELECT count(*) FROM lab WHERE month = '2025-11' AND event_id IN (SELECT event_id FROM bots)) = 0 AS ok,
       format('{} bot events still there', (SELECT count(*) FROM lab WHERE month = '2025-11'
                                             AND event_id IN (SELECT event_id FROM bots))) AS detail
UNION ALL
SELECT 'November kept every other event, exactly once',
       (SELECT count(*) FROM lab WHERE month = '2025-11') = (SELECT count(*) FROM expected_nov)
         AND (SELECT count(DISTINCT event_id) FROM lab WHERE month = '2025-11') = (SELECT count(*) FROM expected_nov),
       format('{} rows in November, expected {}', (SELECT count(*) FROM lab WHERE month = '2025-11'),
              (SELECT count(*) FROM expected_nov))
UNION ALL
SELECT 'October and December are complete',
       (SELECT count(*) FROM lab WHERE month IN ('2025-10', '2025-12'))
         = (SELECT count(*) FROM raw WHERE month IN ('2025-10', '2025-12')),
       format('{} rows, expected {}', (SELECT count(*) FROM lab WHERE month IN ('2025-10', '2025-12')),
              (SELECT count(*) FROM raw WHERE month IN ('2025-10', '2025-12')))
UNION ALL
SELECT 'October and December files were not rewritten',
       (SELECT coalesce(bool_and(last_modified < TIMESTAMPTZ '2026-01-02'), false) FROM files
        WHERE filename NOT LIKE '%month=2025-11%'),
       (SELECT format('{} files outside November, {} rewritten', count(*),
                      count(*) FILTER (WHERE last_modified >= TIMESTAMPTZ '2026-01-02'))
        FROM files WHERE filename NOT LIKE '%month=2025-11%')
