-- Q010 · Time to second order
--
-- lead() puts each order's successor on the same row, so the first order row (rn = 1) carries
-- both timestamps. Users with no second order get NULL, which count(x), avg and percentile_cont
-- all ignore. That's exactly what we want here.
--
-- Note the median is far below the mean: the distribution has a long right tail. When someone
-- asks for "the average", ask which one they mean.
WITH ordered AS (
  SELECT o.user_id,
         o.created_at,
         row_number() OVER w AS rn,
         lead(o.created_at) OVER w AS next_created_at
  FROM orders o
  JOIN users u ON u.user_id = o.user_id
  WHERE NOT u.is_test
  WINDOW w AS (PARTITION BY o.user_id ORDER BY o.created_at, o.order_id)
), firsts AS (
  SELECT user_id, extract(epoch FROM next_created_at - created_at) / 86400 AS days
  FROM ordered
  WHERE rn = 1
    AND created_at >= '2024-01-01' AND created_at < '2025-01-01'
)
SELECT count(*)                                                        AS first_time_buyers,
       count(days)                                                     AS repeat_buyers,
       round(100.0 * count(days) / count(*), 1)                        AS repeat_rate_pct,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY days))::numeric, 1) AS median_days,
       round(avg(days), 1)                                             AS avg_days
FROM firsts;
