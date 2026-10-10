-- Q011 · MoM and YoY growth
--
-- lag(x, 12) means "12 rows back", not "12 months back". It's correct only because every month
-- has revenue. A gap-proof alternative joins the monthly table to itself:
--   LEFT JOIN monthly prev ON prev.month = m.month - interval '1 year'
-- Here you can also see the seasonality: big MoM jumps in Nov/Dec, a drop every January.
WITH monthly AS (
  SELECT date_trunc('month', o.created_at)::date AS month,
         sum(oi.quantity * oi.unit_price)       AS revenue
  FROM orders o
  JOIN order_items oi ON oi.order_id = o.order_id
  JOIN users u        ON u.user_id = o.user_id
  WHERE o.status NOT IN ('cancelled', 'returned')
    AND NOT u.is_test
  GROUP BY 1
), growth AS (
  SELECT month,
         revenue,
         100 * (revenue / lag(revenue) OVER (ORDER BY month) - 1)     AS mom,
         100 * (revenue / lag(revenue, 12) OVER (ORDER BY month) - 1) AS yoy
  FROM monthly
)
SELECT month,
       round(revenue, 2) AS revenue,
       round(mom, 1)     AS mom_growth_pct,
       round(yoy, 1)     AS yoy_growth_pct
FROM growth
WHERE month >= '2024-01-01'
ORDER BY month;
