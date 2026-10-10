-- Q022 · Overlapping subscriptions
--
-- The overlap test for half-open intervals is s1 < e2 AND s2 < e1. Every variant of "do these
-- periods clash?" (bookings, shifts, prices, subscriptions) reduces to it.
--
-- Range-type version of the same join:
--   ON a.user_id = b.user_id AND a.subscription_id < b.subscription_id
--  AND tstzrange(a.started_at, a.ended_at) && tstzrange(b.started_at, b.ended_at)
-- and upper(r1 * r2) - lower(r1 * r2) gives the overlap. In production, an exclusion
-- constraint (EXCLUDE USING gist (user_id WITH =, tstzrange(...) WITH &&)) would have
-- prevented the bug in the first place.
SELECT a.user_id,
       a.subscription_id AS subscription_a,
       b.subscription_id AS subscription_b,
       round((extract(epoch FROM
               least(coalesce(a.ended_at, '2026-01-01'), coalesce(b.ended_at, '2026-01-01'))
               - greatest(a.started_at, b.started_at)) / 86400)::numeric, 1) AS overlap_days
FROM subscriptions a
JOIN subscriptions b
  ON  b.user_id = a.user_id
  AND a.subscription_id < b.subscription_id
  AND a.started_at < coalesce(b.ended_at, 'infinity')
  AND b.started_at < coalesce(a.ended_at, 'infinity')
ORDER BY a.user_id, subscription_a, subscription_b;
