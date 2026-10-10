-- Q007 · Top 3 products per category
--
-- 1. Aggregate revenue per product (at the product grain).
-- 2. Attach the top-level category by joining categories three times.
-- 3. row_number() OVER (PARTITION BY top ORDER BY revenue DESC, product_id) and keep <= 3.
--
-- Why an outer query? Logical evaluation order is FROM -> WHERE -> GROUP BY -> HAVING ->
-- window functions -> SELECT -> ORDER BY -> LIMIT. Window results don't exist yet in WHERE.
--
-- row_number vs rank vs dense_rank on values 10, 10, 9:
--   row_number: 1, 2, 3   rank: 1, 1, 3   dense_rank: 1, 1, 2
WITH product_revenue AS (
  SELECT oi.product_id, sum(oi.quantity * oi.unit_price) AS revenue
  FROM order_items oi
  JOIN orders o ON o.order_id = oi.order_id
  JOIN users u  ON u.user_id = o.user_id
  WHERE o.created_at >= '2025-01-01' AND o.created_at < '2026-01-01'
    AND o.status NOT IN ('cancelled', 'returned')
    AND NOT u.is_test
  GROUP BY oi.product_id
), ranked AS (
  SELECT top.name AS top_category,
         p.product_id,
         p.name   AS product_name,
         pr.revenue,
         row_number() OVER (PARTITION BY top.category_id
                            ORDER BY pr.revenue DESC, p.product_id) AS rank
  FROM product_revenue pr
  JOIN products p      ON p.product_id = pr.product_id
  JOIN categories leaf ON leaf.category_id = p.category_id
  JOIN categories mid  ON mid.category_id = leaf.parent_id
  JOIN categories top  ON top.category_id = mid.parent_id
)
SELECT top_category, rank, product_id, product_name, round(revenue, 2) AS revenue
FROM ranked
WHERE rank <= 3
ORDER BY top_category, rank;
