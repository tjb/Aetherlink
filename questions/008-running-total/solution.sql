-- Q008 · Running total for December
--
-- Aggregate first (one row per day), then window over the aggregated rows. You can nest an
-- aggregate inside a window function directly: sum(sum(x)) OVER (ORDER BY day). The CTE just
-- reads better.
--
-- Frame subtlety: sum(...) OVER (ORDER BY day) uses RANGE UNBOUNDED PRECEDING by default, so
-- rows with the same ORDER BY value ("peers") all get the same running total. Here days are
-- unique so RANGE and ROWS agree; on non-unique keys, say which one you mean.
WITH daily AS (
  SELECT o.created_at::date AS day, sum(oi.quantity * oi.unit_price) AS revenue
  FROM orders o
  JOIN order_items oi ON oi.order_id = o.order_id
  JOIN users u        ON u.user_id = o.user_id
  WHERE o.created_at >= '2025-12-01' AND o.created_at < '2026-01-01'
    AND o.status NOT IN ('cancelled', 'returned')
    AND NOT u.is_test
  GROUP BY 1
)
SELECT day,
       round(revenue, 2)                                                       AS revenue,
       round(sum(revenue) OVER (ORDER BY day), 2)                              AS running_revenue,
       round(100 * sum(revenue) OVER (ORDER BY day) / sum(revenue) OVER (), 1) AS pct_of_month
FROM daily
ORDER BY day;
