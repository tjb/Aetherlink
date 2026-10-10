-- The original (slow) query from the question. Used to compute the expected result.
SELECT event_type, count(*) AS events
FROM events
WHERE date_trunc('day', occurred_at) = '2025-12-31'
GROUP BY event_type;
