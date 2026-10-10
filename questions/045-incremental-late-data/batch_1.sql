-- Batch 1 arrives: it replaces the landing table.
TRUNCATE stream.landing_events;
INSERT INTO stream.landing_events
SELECT 1, event_id, occurred_at, event_type
FROM events
WHERE occurred_at >= '2025-12-01' AND occurred_at < '2026-01-01'
  AND stream.arrival_batch(event_id, occurred_at) = 1;
