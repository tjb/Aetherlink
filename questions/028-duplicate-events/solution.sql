-- Q028 · Duplicate events
--
-- DISTINCT over all business columns is NULL-safe (NULLs group together), so it's the simplest
-- correct dedupe. A self-join with "=" would miss every duplicate whose user_id or product_id
-- is NULL, a quiet undercount.
--
-- In a pipeline you'd keep one copy with:
--   row_number() OVER (PARTITION BY occurred_at, user_id, device, event_type, product_id, properties
--                      ORDER BY event_id) = 1
WITH december AS (
  SELECT occurred_at, user_id, device, event_type, product_id, properties
  FROM events
  WHERE occurred_at >= '2025-12-01' AND occurred_at < '2026-01-01'
), raw AS (
  SELECT occurred_at::date AS day, count(*) AS raw_events
  FROM december GROUP BY 1
), uniq AS (
  SELECT occurred_at::date AS day, count(*) AS unique_events
  FROM (SELECT DISTINCT * FROM december) d
  GROUP BY 1
)
SELECT r.day, r.raw_events, u.unique_events, r.raw_events - u.unique_events AS duplicate_events
FROM raw r
JOIN uniq u ON u.day = r.day
ORDER BY r.day;
