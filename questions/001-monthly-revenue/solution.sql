-- Q001 · Monthly revenue
--
-- Approach: total each order's items first (one row per order), then roll the orders up by month.
--
-- The classic trap is "join fan-out": orders JOIN order_items produces one row per *item*,
-- so COUNT(*) after that join counts items. Pre-aggregating (as here) or COUNT(DISTINCT order_id)
-- both fix it. Pre-aggregating is usually the better habit: each table is summarised at its own
-- grain before being joined, so nothing gets double counted (try SUM over a fanned-out join of
-- two child tables to see why).
WITH order_totals AS (
  SELECT order_id, sum(quantity * unit_price) AS order_value
  FROM order_items
  GROUP BY order_id
)
SELECT date_trunc('month', o.created_at)::date AS month,
       count(*)                                AS orders,
       round(sum(t.order_value), 2)            AS revenue
FROM orders o
JOIN users u        ON u.user_id = o.user_id
JOIN order_totals t ON t.order_id = o.order_id
WHERE o.created_at >= '2025-01-01' AND o.created_at < '2026-01-01'
  AND o.status NOT IN ('cancelled', 'returned')
  AND NOT u.is_test
GROUP BY 1
ORDER BY 1;
