-- Q029 · What time do people buy?
--
-- timestamptz vs timestamp, the one-paragraph version:
--   * timestamptz is an absolute instant. AT TIME ZONE 'X' turns it into the wall-clock time in X
--     (a plain timestamp).
--   * timestamp is a wall-clock reading. AT TIME ZONE 'X' says "this was X's wall clock" and
--     turns it into an instant (timestamptz).
-- Same operator, opposite directions. Store instants (timestamptz) and convert at the edges.
WITH o AS (
  SELECT o.created_at, u.timezone
  FROM orders o
  JOIN users u ON u.user_id = o.user_id
  WHERE o.created_at >= '2025-01-01' AND o.created_at < '2026-01-01'
    AND NOT u.is_test
), local_counts AS (
  SELECT extract(hour FROM created_at AT TIME ZONE timezone)::int AS hour, count(*) AS n
  FROM o GROUP BY 1
), utc_counts AS (
  SELECT extract(hour FROM created_at AT TIME ZONE 'UTC')::int AS hour, count(*) AS n
  FROM o GROUP BY 1
)
SELECT h.hour,
       coalesce(l.n, 0) AS orders_local,
       coalesce(u.n, 0) AS orders_utc
FROM generate_series(0, 23) AS h(hour)
LEFT JOIN local_counts l ON l.hour = h.hour
LEFT JOIN utc_counts u   ON u.hour = h.hour
ORDER BY h.hour;
