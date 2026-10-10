-- Q021 · Subscription MRR
--
-- A date spine CROSS JOIN the facts, with one FILTERed aggregate per measure. Point-in-time
-- questions ("what was true at T?") are always the same predicate on half-open intervals:
--   started_at <= T AND (ended_at IS NULL OR ended_at > T)
-- Postgres range types say the same thing more compactly:
--   tstzrange(started_at, ended_at) @> T     (a NULL upper bound means unbounded)
--
-- The cross join is 12 x |subscriptions|, fine here. For daily snapshots over years you'd
-- want an events-based running sum (+1 at start, -1 at end) instead.
WITH months AS (
  SELECT m AS month_start, m + interval '1 month' AS next_month
  FROM generate_series(timestamptz '2025-01-01', timestamptz '2025-12-01', interval '1 month') AS m
)
SELECT m.month_start::date AS month,
       count(*) FILTER (WHERE s.started_at <= m.next_month
                          AND (s.ended_at IS NULL OR s.ended_at > m.next_month))       AS active_subscriptions,
       round(coalesce(sum(s.monthly_price) FILTER (WHERE s.started_at <= m.next_month
                          AND (s.ended_at IS NULL OR s.ended_at > m.next_month)), 0), 2) AS mrr,
       count(*) FILTER (WHERE s.started_at >= m.month_start AND s.started_at < m.next_month) AS new_subscriptions,
       count(*) FILTER (WHERE s.ended_at   >= m.month_start AND s.ended_at   < m.next_month) AS ended_subscriptions
FROM months m
CROSS JOIN subscriptions s
GROUP BY m.month_start
ORDER BY m.month_start;
