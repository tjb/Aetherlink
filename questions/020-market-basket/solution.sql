-- Q020 · Bought together
--
-- Pair counting = self-join on the basket key with an inequality to avoid (a, a) and (b, a).
-- An order with k distinct products yields k*(k-1)/2 pairs, so a few huge baskets can dominate
-- the cost. In real retail data people cap basket size or sample.
--
-- Raw co-occurrence favours popular products. The next step in real analysis is lift:
-- P(a and b) / (P(a) * P(b)). Try adding it!
WITH baskets AS (
  SELECT DISTINCT oi.order_id, oi.product_id
  FROM order_items oi
  JOIN orders o ON o.order_id = oi.order_id
  JOIN users u  ON u.user_id = o.user_id
  WHERE o.created_at >= '2025-01-01' AND o.created_at < '2026-01-01'
    AND o.status NOT IN ('cancelled', 'returned')
    AND NOT u.is_test
)
SELECT a.product_id AS product_a,
       b.product_id AS product_b,
       count(*)     AS orders_together
FROM baskets a
JOIN baskets b ON b.order_id = a.order_id AND a.product_id < b.product_id
GROUP BY a.product_id, b.product_id
ORDER BY orders_together DESC, product_a, product_b
LIMIT 10;
