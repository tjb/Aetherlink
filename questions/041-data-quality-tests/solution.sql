-- Q041 · Data quality tests
--
-- A data test is a query that returns the rows breaking a rule: 0 rows means it passes. dbt's
-- built-in tests (not_null, unique, relationships, accepted_values) compile to exactly these
-- shapes, and packages like dbt-expectations add ranges, freshness, row counts...
--
-- Where tests run matters:
--   * on the source/staging layer, to stop bad data before it spreads (fail the pipeline, or
--     quarantine the failing rows into a side table);
--   * on the outputs, to catch your own transformation bugs (fan-out duplicates, lost joins).
-- Constraints (PRIMARY KEY, FOREIGN KEY, CHECK, NOT NULL) are tests that run on every write.
-- Warehouses often can't enforce them, which is why ELT pipelines test after loading instead.
SELECT 'order_id_not_null' AS test, count(*) AS failing_rows
FROM dq.orders_snapshot WHERE order_id IS NULL
UNION ALL
SELECT 'order_id_unique', coalesce(sum(n), 0)
FROM (SELECT count(*) AS n FROM dq.orders_snapshot
      WHERE order_id IS NOT NULL GROUP BY order_id HAVING count(*) > 1) d
UNION ALL
SELECT 'user_id_references_users', count(*)
FROM dq.orders_snapshot s
WHERE s.user_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM users u WHERE u.user_id = s.user_id)
UNION ALL
SELECT 'status_accepted_values', count(*)
FROM dq.orders_snapshot
WHERE status IS NULL OR status NOT IN ('pending', 'shipped', 'delivered', 'returned', 'cancelled')
UNION ALL
SELECT 'amount_between_0_and_50000', count(*)
FROM dq.orders_snapshot WHERE amount IS NULL OR amount NOT BETWEEN 0 AND 50000
UNION ALL
SELECT 'shipped_not_before_created', count(*)
FROM dq.orders_snapshot WHERE shipped_at < created_at
UNION ALL
SELECT 'created_not_in_future', count(*)
FROM dq.orders_snapshot WHERE created_at >= '2026-01-01';
