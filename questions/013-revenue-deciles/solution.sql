-- Q013 · Revenue deciles
--
-- ntile(n) deals rows into n buckets as evenly as possible (the first buckets get one extra row
-- when it doesn't divide evenly). A deterministic ORDER BY (here: revenue DESC, user_id) makes
-- bucket boundaries reproducible.
--
-- Windows can run over grouped output: in the final SELECT, sum(revenue) OVER () runs after the
-- GROUP BY decile has produced 10 rows.
WITH customer_revenue AS (
  SELECT o.user_id, sum(oi.quantity * oi.unit_price) AS revenue
  FROM orders o
  JOIN order_items oi ON oi.order_id = o.order_id
  JOIN users u        ON u.user_id = o.user_id
  WHERE o.created_at >= '2025-01-01' AND o.created_at < '2026-01-01'
    AND o.status NOT IN ('cancelled', 'returned')
    AND NOT u.is_test
  GROUP BY o.user_id
), deciles AS (
  SELECT user_id, revenue, ntile(10) OVER (ORDER BY revenue DESC, user_id) AS decile
  FROM customer_revenue
), per_decile AS (
  SELECT decile, count(*) AS customers, sum(revenue) AS revenue
  FROM deciles
  GROUP BY decile
)
SELECT decile,
       customers,
       round(revenue, 2)                                                          AS revenue,
       round(100 * revenue / sum(revenue) OVER (), 1)                             AS pct_of_revenue,
       round(100 * sum(revenue) OVER (ORDER BY decile) / sum(revenue) OVER (), 1) AS cumulative_pct
FROM per_decile
ORDER BY decile;
