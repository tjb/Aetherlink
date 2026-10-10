-- Q031 · Make it sargable
--
-- Setup (run once in ./dojo psql), pick one:
--   CREATE INDEX events_occurred_at_idx ON events (occurred_at);                  -- B-tree
--   CREATE INDEX events_occurred_type_idx ON events (occurred_at, event_type);   -- index-only scan
--   CREATE INDEX events_occurred_brin ON events USING brin (occurred_at);         -- tiny!
--
-- date_trunc('day', occurred_at) = X can't use an index on occurred_at: the planner would have
-- to apply the function to every row first. A plain range on the raw column can ("sargable" =
-- Search ARGument ABLE). Rule of thumb: keep the indexed column bare on one side.
--
-- BRIN fits here because events were inserted in time order, so each block range holds a
-- narrow time window. Compare the sizes: SELECT pg_size_pretty(pg_relation_size('events_occurred_brin'));
-- (An expression index on date_trunc('day', occurred_at) would also work, but it can't
-- serve other range queries.)
SELECT event_type, count(*) AS events
FROM events
WHERE occurred_at >= '2025-12-31' AND occurred_at < '2026-01-01'
GROUP BY event_type;
