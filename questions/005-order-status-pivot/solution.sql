-- Q005 · Order status pivot
--
-- Conditional aggregation: one pass over the table, one aggregate per output column.
-- FILTER is standard SQL (Postgres 9.4+); the CASE form is the portable fallback:
--   sum(CASE WHEN status = 'delivered' THEN 1 ELSE 0 END)
SELECT device,
       count(*) FILTER (WHERE status = 'delivered') AS delivered,
       count(*) FILTER (WHERE status = 'shipped')   AS shipped,
       count(*) FILTER (WHERE status = 'pending')   AS pending,
       count(*) FILTER (WHERE status = 'returned')  AS returned,
       count(*) FILTER (WHERE status = 'cancelled') AS cancelled,
       round(100.0 * count(*) FILTER (WHERE status = 'cancelled') / count(*), 1) AS cancel_rate_pct
FROM orders
WHERE created_at >= '2025-01-01' AND created_at < '2026-01-01'
GROUP BY device
ORDER BY device;
