WITH latest AS (
  SELECT DISTINCT ON (msg->>'order_id') (msg->>'order_id')::bigint AS order_id,
         msg->>'status' AS status, (msg->>'version')::int AS version
  FROM inbox.published
  ORDER BY msg->>'order_id', (msg->>'version')::int DESC
), st AS (
  SELECT l.order_id, l.status, l.version, s.status AS got_status, s.version AS got_version
  FROM latest l FULL JOIN inbox.order_status s USING (order_id)
), orders_truth AS (
  SELECT (msg->>'user_id')::bigint AS user_id, (msg->>'order_id')::bigint AS order_id,
         (msg->>'amount')::numeric AS amount
  FROM inbox.published WHERE msg->>'type' = 'order_placed'
), totals AS (
  SELECT o.user_id, count(*) AS orders, sum(o.amount) AS spent
  FROM orders_truth o JOIN latest l USING (order_id)
  WHERE l.status NOT IN ('cancelled', 'returned')
  GROUP BY o.user_id
), tj AS (
  SELECT user_id, coalesce(t.orders, 0) AS orders, coalesce(t.spent, 0) AS spent,
         coalesce(c.orders, 0) AS got_orders, coalesce(c.spent, 0) AS got_spent
  FROM totals t FULL JOIN inbox.customer_totals c USING (user_id)
  WHERE user_id IN (SELECT user_id FROM orders_truth) OR c.user_id IS NOT NULL
)
SELECT 'every order has a status' AS check,
       count(*) FILTER (WHERE got_status IS NULL) = 0 AND count(*) FILTER (WHERE status IS NULL) = 0 AS ok,
       format('%s of %s orders missing, %s unexpected', count(*) FILTER (WHERE got_status IS NULL),
              count(*) FILTER (WHERE status IS NOT NULL), count(*) FILTER (WHERE status IS NULL)) AS detail
FROM st
UNION ALL
SELECT 'an old message never overwrites a newer status',
       count(*) FILTER (WHERE got_version < version OR got_status <> status) = 0,
       format('%s orders show an older status', count(*) FILTER (WHERE got_version < version OR got_status <> status))
       || coalesce(', e.g. ' || min(format('order %s is %s (v%s), should be %s (v%s)', order_id, got_status,
                                           got_version, status, version))
                                FILTER (WHERE got_version < version OR got_status <> status), '')
FROM st
UNION ALL
SELECT 'order counts per customer: each message counted once',
       count(*) FILTER (WHERE got_orders <> orders) = 0,
       format('%s customers wrong', count(*) FILTER (WHERE got_orders <> orders))
       || coalesce(', e.g. ' || min(format('user %s: %s orders, should be %s', user_id, got_orders, orders))
                                FILTER (WHERE got_orders <> orders), '')
FROM tj
UNION ALL
SELECT 'amount spent per customer: each message counted once',
       count(*) FILTER (WHERE got_spent <> spent) = 0,
       format('%s customers wrong', count(*) FILTER (WHERE got_spent <> spent))
       || coalesce(', e.g. ' || min(format('user %s: %s, should be %s', user_id, got_spent, spent))
                                FILTER (WHERE got_spent <> spent), '')
FROM tj;
