-- Q034 · TRUNCATE blast radius
--
-- TRUNCATE ... CASCADE follows foreign keys *backwards* (from parent to every child that
-- references it), recursively, and empties everything it reaches. In one statement, with no
-- per-row triggers and no WHERE clause. Here, resetting users also wipes orders, order_items,
-- reviews and subscriptions.
--
-- The recursion walks pg_constraint from parent to child. users.referred_by -> users is a
-- self-reference, so without a cycle guard the CTE loops forever. The path array stops it
-- (Postgres 14+ alternative: CYCLE rel SET is_cycle USING path).
--
-- Things worth knowing about TRUNCATE (vs DELETE) in Postgres:
--   * It needs its own TRUNCATE privilege. Having DELETE isn't enough (see Q035).
--   * It takes an ACCESS EXCLUSIVE lock: even plain SELECTs on the table wait (see Q037).
--   * It's transactional in Postgres (you can ROLLBACK it). In MySQL it's DDL with an
--     implicit commit and can't be undone.
--   * Without CASCADE it fails if any other table references this one, which is a useful
--     safety net. CASCADE removes the safety net.
--   * It doesn't fire ON DELETE triggers (only ON TRUNCATE triggers) and doesn't scan rows,
--     which is why it's instant.
WITH RECURSIVE fk AS (
  SELECT conrelid AS child, confrelid AS parent
  FROM pg_constraint
  WHERE contype = 'f'
), blast AS (
  SELECT 'users'::regclass::oid AS rel, 0 AS hops, ARRAY['users'::regclass::oid] AS path
  UNION ALL
  SELECT fk.child, b.hops + 1, b.path || fk.child
  FROM blast b
  JOIN fk ON fk.parent = b.rel
  WHERE fk.child <> ALL (b.path)
)
SELECT rel::regclass::text AS table_name, min(hops) AS hops
FROM blast
GROUP BY rel
ORDER BY hops, table_name;
