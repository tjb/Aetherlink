-- Q026 · Latest orders with LATERAL
--
-- LATERAL = "for each row on the left, run this subquery". Combined with ORDER BY ... LIMIT
-- it's the most efficient top-N-per-group when the groups are few and an index can feed
-- the ORDER BY: here orders_user_id_idx finds each user's orders directly.
-- row_number() over all orders would rank every order of every user and throw most away.
WITH top_users AS (
  SELECT o.user_id
  FROM orders o
  JOIN users u ON u.user_id = o.user_id
  WHERE NOT u.is_test
  GROUP BY o.user_id
  ORDER BY count(*) DESC, o.user_id
  LIMIT 20
)
SELECT t.user_id, r.order_id, r.created_at, r.order_total
FROM top_users t
CROSS JOIN LATERAL (
  SELECT o.order_id,
         o.created_at,
         (SELECT round(sum(oi.quantity * oi.unit_price), 2)
          FROM order_items oi WHERE oi.order_id = o.order_id) AS order_total
  FROM orders o
  WHERE o.user_id = t.user_id
  ORDER BY o.created_at DESC, o.order_id DESC
  LIMIT 3
) r
ORDER BY t.user_id, r.created_at DESC;
