-- Q023 · Delivery time percentiles
--
-- Means hide tails. USPS has a decent median but an ugly p90/p99. That's what customers
-- remember, and why latency SLOs are written as percentiles.
--
-- percentile_cont interpolates between neighbouring values; percentile_disc returns an actual
-- value from the data. Both sort their input, so they cost O(n log n) per group.
WITH d AS (
  SELECT carrier, extract(epoch FROM delivered_at - shipped_at) / 3600 AS hours
  FROM orders
  WHERE shipped_at >= '2025-01-01' AND shipped_at < '2026-01-01'
    AND delivered_at IS NOT NULL
)
SELECT carrier,
       count(*) FILTER (WHERE hours >= 0) AS deliveries,
       round((percentile_cont(0.50) WITHIN GROUP (ORDER BY hours) FILTER (WHERE hours >= 0))::numeric, 1) AS p50_hours,
       round((percentile_cont(0.90) WITHIN GROUP (ORDER BY hours) FILTER (WHERE hours >= 0))::numeric, 1) AS p90_hours,
       round((percentile_cont(0.99) WITHIN GROUP (ORDER BY hours) FILTER (WHERE hours >= 0))::numeric, 1) AS p99_hours,
       count(*) FILTER (WHERE hours < 0) AS bad_records
FROM d
GROUP BY carrier
ORDER BY p90_hours DESC;
