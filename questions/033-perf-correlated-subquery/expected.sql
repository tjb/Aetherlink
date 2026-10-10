-- Equivalent to the (very slow) correlated query in the question, rewritten as a join so the
-- expected result can be computed in seconds even without indexes.
WITH o AS (
  SELECT o.order_id, o.user_id, o.device, o.created_at
  FROM orders o
  JOIN users u ON u.user_id = o.user_id
  WHERE NOT u.is_test
    AND o.created_at >= '2025-01-01' AND o.created_at < '2026-01-01'
), per_order AS (
  SELECT o.order_id, o.device, count(e.event_id) AS n
  FROM o
  LEFT JOIN events e
    ON  e.user_id = o.user_id
    AND e.occurred_at >= o.created_at - interval '24 hours'
    AND e.occurred_at <  o.created_at
  GROUP BY o.order_id, o.device
)
SELECT device, count(*) AS orders, round(avg(n), 2) AS avg_events_before
FROM per_order
GROUP BY device
ORDER BY device;
