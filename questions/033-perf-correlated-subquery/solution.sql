-- Q033 · Events before purchase
--
-- Setup (run once in ./dojo psql):
--   CREATE INDEX events_user_time_idx ON events (user_id, occurred_at);
--
-- The correlated subquery runs once per order. Without an index, each run scans all ~6M
-- events: ~50k orders x a full scan = hours. With an index on (user_id, occurred_at), each
-- run is one small range scan, and the original query is suddenly fine. The fix was the
-- index, not a rewrite.
--
-- The join rewrite below is what the planner would love to do itself (it can't decorrelate
-- an aggregate subquery). With the index it runs as a nested loop of index range scans;
-- without it, a hash join. Both beat the per-row scans by orders of magnitude.
WITH o AS (
  SELECT o.order_id, o.user_id, o.device, o.created_at
  FROM orders o
  JOIN users u ON u.user_id = o.user_id
  WHERE NOT u.is_test
    AND o.created_at >= '2025-01-01' AND o.created_at < '2026-01-01'
)
SELECT o.device,
       count(*) AS orders,
       round(avg(c.n), 2) AS avg_events_before
FROM o
CROSS JOIN LATERAL (
  SELECT count(*) AS n
  FROM events e
  WHERE e.user_id = o.user_id
    AND e.occurred_at >= o.created_at - interval '24 hours'
    AND e.occurred_at <  o.created_at
) c
GROUP BY o.device
ORDER BY o.device;
