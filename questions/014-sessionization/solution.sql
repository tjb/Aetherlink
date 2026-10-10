-- Q014 · Sessionization
--
-- The canonical pattern:
--   1. LAG to see the previous event.
--   2. A 0/1 flag marking where a new group starts.
--   3. A running SUM of the flag -> a group number.
--   4. GROUP BY the group number.
-- The same shape solves "consecutive days" (Q017), "status changes", "streaks", and more.
--
-- This sorts ~half a million rows per month twice (once per window, same sort key, so the
-- planner shares it). Try EXPLAIN (ANALYZE) on it and look for "Sort Method: external merge":
-- that means work_mem was too small and the sort spilled to disk.
WITH ev AS (
  SELECT e.user_id, e.event_id, e.occurred_at, e.device,
         lag(e.occurred_at) OVER (PARTITION BY e.user_id ORDER BY e.occurred_at, e.event_id) AS prev_at
  FROM events e
  JOIN users u ON u.user_id = e.user_id
  WHERE e.occurred_at >= '2025-12-01' AND e.occurred_at < '2026-01-01'
    AND NOT u.is_test
), flagged AS (
  SELECT *,
         CASE WHEN prev_at IS NULL OR occurred_at - prev_at > interval '30 minutes' THEN 1 ELSE 0 END AS new_session
  FROM ev
), numbered AS (
  SELECT *,
         sum(new_session) OVER (PARTITION BY user_id ORDER BY occurred_at, event_id) AS session_no
  FROM flagged
), sessions AS (
  SELECT user_id,
         session_no,
         (array_agg(device ORDER BY occurred_at, event_id))[1]      AS device,
         count(*)                                                   AS events,
         extract(epoch FROM max(occurred_at) - min(occurred_at)) / 60 AS minutes
  FROM numbered
  GROUP BY user_id, session_no
)
SELECT device,
       count(*)               AS sessions,
       round(avg(events), 1)  AS avg_events,
       round(avg(minutes), 1) AS avg_minutes
FROM sessions
GROUP BY device
ORDER BY device;
