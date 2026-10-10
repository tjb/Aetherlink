-- Q015 · Ordered conversion funnel
--
-- Each step needs the time of the previous step's first *qualifying* event, so the steps have
-- to be computed in sequence. Two ways to do it:
--
-- (a) Chained CTEs: s1 = min(product_view) per user-day, then s2 joins s1 back to the events
--     with occurred_at > s1.t and takes min() again, and so on. Readable, but every CTE scan
--     gets a crude row estimate, and with four layers the planner can pick a nested loop that
--     compares every s3 row with every event: about a minute instead of a fraction of a
--     second. Run it with EXPLAIN ANALYZE and compare estimated vs actual rows. This is the
--     #1 cause of mysteriously slow SQL.
--
-- (b) Below: layered window aggregates over the same partition. min(...) FILTER (...) OVER
--     (PARTITION BY user_id, day) stamps every event of the user-day with the step time, and
--     each layer can refer to the previous layer's column. One sort, no joins.
WITH ev AS (
  SELECT e.user_id, e.occurred_at::date AS day, e.event_type, e.occurred_at
  FROM events e
  JOIN users u ON u.user_id = e.user_id
  WHERE e.occurred_at >= '2025-11-01' AND e.occurred_at < '2025-12-01'
    AND NOT u.is_test
    AND e.event_type IN ('product_view', 'add_to_cart', 'checkout_started', 'purchase')
), l1 AS (
  SELECT *, min(occurred_at) FILTER (WHERE event_type = 'product_view') OVER w AS t1
  FROM ev
  WINDOW w AS (PARTITION BY user_id, day)
), l2 AS (
  SELECT *, min(occurred_at) FILTER (WHERE event_type = 'add_to_cart' AND occurred_at > t1) OVER w AS t2
  FROM l1
  WINDOW w AS (PARTITION BY user_id, day)
), l3 AS (
  SELECT *, min(occurred_at) FILTER (WHERE event_type = 'checkout_started' AND occurred_at > t2) OVER w AS t3
  FROM l2
  WINDOW w AS (PARTITION BY user_id, day)
), l4 AS (
  SELECT *, min(occurred_at) FILTER (WHERE event_type = 'purchase' AND occurred_at > t3) OVER w AS t4
  FROM l3
  WINDOW w AS (PARTITION BY user_id, day)
), user_days AS (
  SELECT user_id, day, max(t1) AS t1, max(t2) AS t2, max(t3) AS t3, max(t4) AS t4
  FROM l4
  GROUP BY user_id, day
), counts AS (
  SELECT 1 AS step, 'product_view' AS event_type, count(t1) AS user_days FROM user_days
  UNION ALL SELECT 2, 'add_to_cart',      count(t2) FROM user_days
  UNION ALL SELECT 3, 'checkout_started', count(t3) FROM user_days
  UNION ALL SELECT 4, 'purchase',         count(t4) FROM user_days
)
SELECT step,
       event_type,
       user_days,
       round(100.0 * user_days / lag(user_days) OVER (ORDER BY step), 1)         AS pct_of_previous,
       round(100.0 * user_days / first_value(user_days) OVER (ORDER BY step), 1) AS pct_of_step1
FROM counts
ORDER BY step;
