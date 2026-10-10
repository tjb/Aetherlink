-- Q009 · Moving average with gaps
--
-- Two classic mistakes:
--  1. Not filling gaps: a ROWS frame of 7 rows spans MORE than 7 days when days are missing.
--     (A RANGE frame with an interval offset, RANGE BETWEEN interval '6 days' PRECEDING AND
--     CURRENT ROW, is gap-proof, but zero days still wouldn't appear in the output.)
--  2. Filtering in the same query as the window: WHERE runs before window functions, so
--     January 1st would only "see" itself. Compute the window over a wider range, then filter.
WITH calendar AS (
  SELECT d::date AS day
  FROM generate_series(date '2024-12-26', date '2025-03-31', interval '1 day') AS d
), daily AS (
  SELECT signup_at::date AS day, count(*) AS signups
  FROM users
  WHERE country = 'ES' AND NOT is_test
    AND signup_at >= '2024-12-26' AND signup_at < '2025-04-01'
  GROUP BY 1
), series AS (
  SELECT c.day,
         coalesce(d.signups, 0) AS signups,
         avg(coalesce(d.signups, 0)) OVER (ORDER BY c.day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS avg_7d
  FROM calendar c
  LEFT JOIN daily d ON d.day = c.day
)
SELECT day, signups, round(avg_7d, 2) AS avg_7d
FROM series
WHERE day >= '2025-01-01'
ORDER BY day;
