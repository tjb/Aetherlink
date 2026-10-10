-- Q024 · Subtotals with CUBE
--
-- CUBE(a, b) computes four groupings in one pass: (a, b), (a), (b), (). Without it you'd
-- UNION ALL four GROUP BY queries and scan the data four times.
--
-- GROUPING(x) = 1 means "x was rolled up in this row". Prefer it to coalesce(x, 'All'):
-- coalesce can't tell a subtotal from a genuine NULL in the data.
SELECT CASE WHEN grouping(top.name) = 1 THEN 'All' ELSE top.name END AS top_category,
       CASE WHEN grouping(o.device) = 1 THEN 'All' ELSE o.device END AS device,
       round(sum(oi.quantity * oi.unit_price), 2)                      AS revenue
FROM order_items oi
JOIN orders o        ON o.order_id = oi.order_id
JOIN users u         ON u.user_id = o.user_id
JOIN products p      ON p.product_id = oi.product_id
JOIN categories leaf ON leaf.category_id = p.category_id
JOIN categories mid  ON mid.category_id = leaf.parent_id
JOIN categories top  ON top.category_id = mid.parent_id
WHERE o.created_at >= '2025-01-01' AND o.created_at < '2026-01-01'
  AND o.status NOT IN ('cancelled', 'returned')
  AND NOT u.is_test
GROUP BY CUBE (top.name, o.device)
ORDER BY grouping(top.name), top.name, grouping(o.device), o.device;
