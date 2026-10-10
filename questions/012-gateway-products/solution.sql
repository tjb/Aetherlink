-- Q012 · Gateway products
--
-- DISTINCT ON (key) + ORDER BY key, <preference> keeps the "best" row per key. It's Postgres
-- only, but it's concise and usually fast (one sort, or an index scan if one matches).
-- Portable equivalent: row_number() OVER (PARTITION BY user_id ORDER BY created_at, order_id) = 1.
--
-- count(DISTINCT user_id) guards against the same product appearing on two lines of one order.
WITH first_orders AS (
  SELECT DISTINCT ON (o.user_id) o.user_id, o.order_id
  FROM orders o
  JOIN users u ON u.user_id = o.user_id
  WHERE NOT u.is_test
  ORDER BY o.user_id, o.created_at, o.order_id
)
SELECT p.product_id,
       p.name                    AS product_name,
       count(DISTINCT f.user_id) AS first_order_users
FROM first_orders f
JOIN order_items oi ON oi.order_id = f.order_id
JOIN products p     ON p.product_id = oi.product_id
GROUP BY p.product_id, p.name
ORDER BY first_order_users DESC, p.product_id
LIMIT 10;
