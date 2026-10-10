-- Q046 · Partitioning and retention
--
-- Declarative partitioning: the parent table holds no data; each row is routed to the partition
-- whose bounds contain its partition key. The planner then skips partitions that can't match a
-- WHERE clause ("partition pruning"), at plan time for constants and at run time for
-- parameters.
--
-- Retention by DROP (or DETACH, to archive somewhere first) is a metadata operation: instant,
-- no per-row WAL, no dead tuples, no VACUUM. Compare deleting 9 months of rows (Q036).
--
-- Things to know before partitioning in production:
--   * Primary keys and unique constraints must include the partition key.
--   * Queries that don't filter on the key scan every partition, so pick the key your queries
--     filter on (usually time).
--   * Thousands of partitions slow down planning. Months or days, not minutes.
--   * Something must create future partitions before data arrives (a cron job, pg_partman), or
--     inserts fail. A DEFAULT partition catches strays, but then must be emptied before you can
--     add a partition overlapping its rows.
--   * ATTACH PARTITION lets you load a table offline and swap it in.
CREATE TABLE archive.events (LIKE public.events) PARTITION BY RANGE (occurred_at);

SELECT format('CREATE TABLE archive.events_%s PARTITION OF archive.events FOR VALUES FROM (%L) TO (%L)',
              to_char(m, 'YYYY_MM'), m, m + interval '1 month')
FROM generate_series(timestamptz '2025-01-01', timestamptz '2025-12-01', interval '1 month') AS m
\gexec

INSERT INTO archive.events
SELECT * FROM public.events
WHERE occurred_at >= '2025-01-01' AND occurred_at < '2026-01-01';

-- retention: keep Q4 only
SELECT format('DROP TABLE archive.events_%s', to_char(m, 'YYYY_MM'))
FROM generate_series(timestamptz '2025-01-01', timestamptz '2025-09-01', interval '1 month') AS m
\gexec

EXPLAIN SELECT count(*) FROM archive.events
WHERE occurred_at >= '2025-12-24' AND occurred_at < '2025-12-25';
