-- Q017 · Longest daily streak
--
-- Gaps and islands: within a run of consecutive dates, date - row_number() is constant, so
-- that difference identifies the island. (The LAG + running SUM approach from Q014 works too.
-- Try both and compare the plans.)
--
-- DISTINCT ON (user_id) ... ORDER BY user_id, streak_days DESC, streak_start picks each
-- user's best streak, earliest first on ties.
WITH active_days AS (
  SELECT DISTINCT e.user_id, e.occurred_at::date AS day
  FROM events e
  JOIN users u ON u.user_id = e.user_id
  WHERE e.occurred_at >= '2025-01-01' AND e.occurred_at < '2026-01-01'
    AND NOT u.is_test
), islands AS (
  SELECT user_id, day,
         day - (row_number() OVER (PARTITION BY user_id ORDER BY day))::int AS island
  FROM active_days
), streaks AS (
  SELECT user_id, min(day) AS streak_start, max(day) AS streak_end, count(*) AS streak_days
  FROM islands
  GROUP BY user_id, island
), best AS (
  SELECT DISTINCT ON (user_id) user_id, streak_days, streak_start, streak_end
  FROM streaks
  ORDER BY user_id, streak_days DESC, streak_start
)
SELECT user_id, streak_days, streak_start, streak_end
FROM best
ORDER BY streak_days DESC, user_id
LIMIT 10;
