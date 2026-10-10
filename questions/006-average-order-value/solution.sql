-- Q006 · Average order value by country
--
-- Two levels of aggregation: items -> order totals -> country averages.
-- Averaging line items instead would weight multi-item orders more heavily and give a smaller,
-- wrong number. Always ask "what is one row?" before you aggregate.
--
-- The 3% threshold uses the CTE twice. Alternative: compute the share with a window function
-- over the grouped rows: count(*) * 1.0 / sum(count(*)) OVER () >= 0.03 (in an outer query).
WITH order_totals AS (
  SELECT o.order_id, o.ship_country, sum(oi.quantity * oi.unit_price) AS total
  FROM orders o
  JOIN order_items oi ON oi.order_id = o.order_id
  JOIN users u        ON u.user_id = o.user_id
  WHERE o.status = 'delivered'
    AND o.created_at >= '2025-01-01' AND o.created_at < '2026-01-01'
    AND NOT u.is_test
  GROUP BY o.order_id, o.ship_country
)
SELECT ship_country           AS country,
       count(*)               AS orders,
       round(avg(total), 2)   AS aov
FROM order_totals
GROUP BY ship_country
HAVING count(*) >= 0.03 * (SELECT count(*) FROM order_totals)
ORDER BY aov DESC;
