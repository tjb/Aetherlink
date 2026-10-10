WITH rg AS (
  SELECT row_group_id, row_group_num_rows AS n,
         TRY_CAST(stats_min_value AS BIGINT) AS lo, TRY_CAST(stats_max_value AS BIGINT) AS hi
  FROM parquet_metadata('lake/gold/events_by_user.parquet')
  WHERE path_in_schema = 'user_id'
), ordered AS (
  SELECT *, lag(hi) OVER (ORDER BY row_group_id) AS prev_hi FROM rg
), probe AS (  -- a few users spread over the id range
  SELECT unnest([min(user_id), quantile_disc(user_id, 0.25), quantile_disc(user_id, 0.5),
                 quantile_disc(user_id, 0.9), max(user_id)]) AS uid
  FROM read_csv('lake/raw/users.csv.gz')
), lookups AS (
  SELECT p.uid, count(r.row_group_id) AS groups
  FROM probe p LEFT JOIN rg r ON p.uid BETWEEN r.lo AND r.hi
  GROUP BY p.uid
)
SELECT 'the file holds every event' AS check,
       (SELECT sum(n) FROM rg) = (SELECT events FROM read_json('lake/.built.json')) AS ok,
       format('{} rows, {} events in the lake', (SELECT sum(n) FROM rg), (SELECT events FROM read_json('lake/.built.json'))) AS detail
UNION ALL
SELECT 'row groups of about 100,000 rows',
       (SELECT max(n) FROM rg) <= 102400 AND (SELECT count(*) FROM rg) >= ceil((SELECT sum(n) FROM rg) / 102400),
       format('{} row groups, largest {} rows', (SELECT count(*) FROM rg), (SELECT max(n) FROM rg))
UNION ALL
SELECT 'row groups are sorted by user_id (ranges don''t overlap)',
       (SELECT count(*) FILTER (WHERE lo < prev_hi) FROM ordered) = 0,
       format('{} overlapping row groups', (SELECT count(*) FILTER (WHERE lo < prev_hi) FROM ordered))
UNION ALL
SELECT 'looking up one user needs at most 2 row groups',
       (SELECT max(groups) FROM lookups) <= 2,
       format('worst case: {} row groups', (SELECT max(groups) FROM lookups))
