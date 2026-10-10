-- Q016 · Cohort retention
--
-- Shape: cohort assignment -> distinct activity months -> month offset -> count per cell,
-- then a dense grid LEFT JOINed with the counts so empty cells show 0 instead of vanishing.
--
-- Month 0 is not 100%: some users signed up while logged out or never fired another event.
-- Reading the table diagonally (same calendar month across cohorts) separates seasonality
-- from cohort quality.
WITH cohorts AS (
  SELECT user_id, date_trunc('month', signup_at)::date AS cohort_month
  FROM users
  WHERE NOT is_test
    AND signup_at >= '2025-01-01' AND signup_at < '2025-07-01'
), activity AS (
  SELECT DISTINCT e.user_id, date_trunc('month', e.occurred_at)::date AS active_month
  FROM events e
  JOIN cohorts c ON c.user_id = e.user_id
  WHERE e.occurred_at >= '2025-01-01'
), cells AS (
  SELECT c.cohort_month,
         ((extract(year FROM a.active_month) - extract(year FROM c.cohort_month)) * 12
          + extract(month FROM a.active_month) - extract(month FROM c.cohort_month))::int AS month_number,
         count(*) AS active_users
  FROM cohorts c
  JOIN activity a ON a.user_id = c.user_id
  GROUP BY 1, 2
), sizes AS (
  SELECT cohort_month, count(*) AS cohort_size FROM cohorts GROUP BY cohort_month
)
SELECT s.cohort_month,
       s.cohort_size,
       m.month_number,
       coalesce(c.active_users, 0)                                   AS active_users,
       round(100.0 * coalesce(c.active_users, 0) / s.cohort_size, 1) AS retention_pct
FROM sizes s
CROSS JOIN generate_series(0, 6) AS m(month_number)
LEFT JOIN cells c ON c.cohort_month = s.cohort_month AND c.month_number = m.month_number
ORDER BY s.cohort_month, m.month_number;
