WITH truth AS (
  SELECT occurred_at::date AS day, event_type, count(*) AS events
  FROM events
  WHERE occurred_at >= '2025-12-01' AND occurred_at < '2026-01-01'
  GROUP BY 1, 2
), j AS (
  SELECT t.day, t.event_type, t.events, c.events AS got
  FROM truth t FULL JOIN stream.daily_event_counts c USING (day, event_type)
)
SELECT 'every December day and event type has a row' AS check,
       count(*) FILTER (WHERE got IS NULL) = 0 AND count(*) FILTER (WHERE events IS NULL) = 0 AS ok,
       format('%s missing, %s unexpected', count(*) FILTER (WHERE got IS NULL), count(*) FILTER (WHERE events IS NULL)) AS detail
FROM j
UNION ALL
SELECT 'no batch was counted twice (retries are safe)',
       count(*) FILTER (WHERE got > events) = 0,
       coalesce(min(format('%s %s: %s counted, %s delivered', day, event_type, got, events))
                FILTER (WHERE got > events), '')
FROM j
UNION ALL
SELECT 'late events were added to the days they belong to',
       count(*) FILTER (WHERE got < events) = 0,
       coalesce(min(format('%s %s: %s counted, %s delivered', day, event_type, got, events))
                FILTER (WHERE got < events), '')
FROM j
UNION ALL
SELECT 'grand total matches',
       (SELECT coalesce(sum(events), 0) FROM stream.daily_event_counts) = (SELECT sum(events) FROM truth),
       format('%s counted, %s delivered', (SELECT coalesce(sum(events), 0) FROM stream.daily_event_counts),
              (SELECT sum(events) FROM truth))
