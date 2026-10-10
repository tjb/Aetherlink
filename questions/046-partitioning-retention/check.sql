CREATE FUNCTION pg_temp.relations_scanned(q text) RETURNS int LANGUAGE plpgsql AS $$
DECLARE plan json;
BEGIN
  EXECUTE 'EXPLAIN (FORMAT JSON) ' || q INTO plan;
  RETURN (SELECT count(*) FROM regexp_matches(plan::text, '"Relation Name"', 'g'));
END $$;

-- count(*) of a table that may not exist (NULL if it doesn't)
CREATE FUNCTION pg_temp.row_count(t text) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
  IF to_regclass(t) IS NULL THEN RETURN NULL; END IF;
  EXECUTE format('SELECT count(*) FROM %s', t) INTO n;
  RETURN n;
END $$;

WITH parts AS (
  SELECT c.relname, pg_get_expr(c.relpartbound, c.oid) AS bound
  FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid
  WHERE i.inhparent = to_regclass('archive.events')
), months AS (
  SELECT format('events_2025_%s', to_char(m, 'MM')) AS relname,
         format('FOR VALUES FROM (%L) TO (%L)', m, m + interval '1 month') AS bound
  FROM generate_series(timestamptz '2025-10-01', timestamptz '2025-12-01', interval '1 month') AS m
)
SELECT 'archive.events is range-partitioned on occurred_at' AS check,
       coalesce((SELECT pt.partstrat = 'r'
                        AND (SELECT attname FROM pg_attribute
                             WHERE attrelid = pt.partrelid AND attnum = pt.partattrs[0]) = 'occurred_at'
                 FROM pg_partitioned_table pt WHERE pt.partrelid = to_regclass('archive.events')), false) AS ok,
       CASE WHEN to_regclass('archive.events') IS NULL THEN 'archive.events does not exist' ELSE '' END AS detail
UNION ALL
SELECT 'only the Q4 partitions remain: events_2025_10, _11, _12',
       (SELECT array_agg(relname ORDER BY relname) FROM parts) IS NOT DISTINCT FROM
         ARRAY['events_2025_10', 'events_2025_11', 'events_2025_12']::name[],
       'partitions: ' || coalesce((SELECT string_agg(relname, ', ' ORDER BY relname) FROM parts), 'none')
UNION ALL
SELECT 'each partition covers exactly its calendar month (UTC)',
       (SELECT count(*) FROM months m JOIN parts p ON p.relname = m.relname AND p.bound = m.bound) = 3,
       coalesce((SELECT min(p.relname || ': ' || p.bound) FROM parts p
                 LEFT JOIN months m ON m.relname = p.relname AND m.bound = p.bound WHERE m.relname IS NULL), '')
UNION ALL
SELECT 'January-September were dropped, not kept as tables',
       NOT EXISTS (SELECT 1 FROM generate_series(1, 9) AS n
                   WHERE to_regclass(format('archive.events_2025_%s', lpad(n::text, 2, '0'))) IS NOT NULL), ''
UNION ALL
SELECT 'it holds exactly the Q4 2025 events',
       pg_temp.row_count('archive.events')
         IS NOT DISTINCT FROM (SELECT count(*) FROM events WHERE occurred_at >= '2025-10-01' AND occurred_at < '2026-01-01'),
       format('%s rows, expected %s', coalesce(pg_temp.row_count('archive.events')::text, 'no table'),
              (SELECT count(*) FROM events WHERE occurred_at >= '2025-10-01' AND occurred_at < '2026-01-01'))
UNION ALL
SELECT 'a one-day query reads a single partition (pruning)',
       CASE WHEN to_regclass('archive.events') IS NULL THEN false
            ELSE pg_temp.relations_scanned(
                   'SELECT count(*) FROM archive.events WHERE occurred_at >= ''2025-12-24'' AND occurred_at < ''2025-12-25''') = 1
       END,
       ''
