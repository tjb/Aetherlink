-- Q030 · Latest activity per user
--
-- Setup (run once in ./dojo psql):
--   CREATE INDEX events_user_time_idx ON events (user_id, occurred_at DESC, event_id DESC);
--   CREATE INDEX users_signup_idx     ON users (signup_at, user_id);
--
-- Why it's fast: for each of the 100 users, LATERAL ... ORDER BY ... LIMIT 1 becomes a single
-- descent of the B-tree to that user's newest entry: about 100 x 4 page reads in total.
-- The original query joins all ~6M events and sorts them to keep 100 rows.
--
-- The index column order matters: equality columns first (user_id), then the sort columns
-- in the same direction as the ORDER BY. A B-tree can be read backwards, so
-- (user_id, occurred_at, event_id) works too.
WITH first_users AS (
  SELECT user_id
  FROM users
  WHERE NOT is_test
  ORDER BY signup_at, user_id
  LIMIT 100
)
SELECT f.user_id,
       last.occurred_at AS last_event_at,
       last.event_type  AS last_event_type
FROM first_users f
LEFT JOIN LATERAL (
  SELECT e.occurred_at, e.event_type
  FROM events e
  WHERE e.user_id = f.user_id
  ORDER BY e.occurred_at DESC, e.event_id DESC
  LIMIT 1
) last ON true;
