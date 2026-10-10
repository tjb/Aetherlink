-- Q027 · Tracking loss (JSONB)
--
-- Reconciliation between two systems is a daily data-engineering job. The shape:
-- build the set of keys system B knows about (DISTINCT kills duplicate deliveries), then
-- LEFT JOIN from system A and count the misses.
--
-- To make this fast at scale, index the expression you join on:
--   CREATE INDEX ON events (((properties ->> 'order_id')::bigint)) WHERE event_type = 'purchase';
-- A partial expression index covering only purchase events stays tiny.
WITH tracked AS (
  SELECT DISTINCT (properties ->> 'order_id')::bigint AS order_id
  FROM events
  WHERE event_type = 'purchase'
)
SELECT o.device,
       count(*)                                  AS orders,
       count(*) FILTER (WHERE t.order_id IS NULL) AS orders_missing_event,
       round(100.0 * count(*) FILTER (WHERE t.order_id IS NULL) / count(*), 2) AS pct_missing
FROM orders o
LEFT JOIN tracked t ON t.order_id = o.order_id
WHERE o.created_at >= '2025-01-01' AND o.created_at < '2026-01-01'
GROUP BY o.device
ORDER BY o.device;
