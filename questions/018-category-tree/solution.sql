-- Q018 · Category tree rollup
--
-- paths:   walks down from the roots, accumulating the path string and depth.
-- closure: every (ancestor, descendant) pair, including (x, x). Joining facts on the
--          descendant and grouping by the ancestor is the general way to roll up a hierarchy.
--
-- Recursive CTEs evaluate iteratively: run the anchor, then repeatedly run the recursive part
-- against only the rows produced by the previous iteration, until no new rows appear.
-- With cyclic data that never ends. Postgres 14+ has CYCLE ... SET ... USING to guard against it.
WITH RECURSIVE paths AS (
  SELECT category_id, name::text AS path, 1 AS depth
  FROM categories
  WHERE parent_id IS NULL
  UNION ALL
  SELECT c.category_id, p.path || ' > ' || c.name, p.depth + 1
  FROM categories c
  JOIN paths p ON c.parent_id = p.category_id
), closure AS (
  SELECT category_id AS ancestor_id, category_id AS descendant_id
  FROM categories
  UNION ALL
  SELECT cl.ancestor_id, c.category_id
  FROM closure cl
  JOIN categories c ON c.parent_id = cl.descendant_id
), category_revenue AS (
  SELECT p.category_id, sum(oi.quantity * oi.unit_price) AS revenue
  FROM order_items oi
  JOIN orders o   ON o.order_id = oi.order_id
  JOIN users u    ON u.user_id = o.user_id
  JOIN products p ON p.product_id = oi.product_id
  WHERE o.created_at >= '2025-01-01' AND o.created_at < '2026-01-01'
    AND o.status NOT IN ('cancelled', 'returned')
    AND NOT u.is_test
  GROUP BY p.category_id
)
SELECT pa.category_id,
       pa.path,
       pa.depth,
       round(coalesce(sum(cr.revenue), 0), 2) AS revenue
FROM paths pa
JOIN closure cl              ON cl.ancestor_id = pa.category_id
LEFT JOIN category_revenue cr ON cr.category_id = cl.descendant_id
GROUP BY pa.category_id, pa.path, pa.depth
ORDER BY pa.path;
