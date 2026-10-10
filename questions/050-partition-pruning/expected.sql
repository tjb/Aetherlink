-- The same question answered from the raw CSV files.
SELECT device, count(*) AS purchases
FROM read_csv('lake/raw/events/*/*.csv.gz', hive_partitioning = true)
WHERE day = DATE '2025-12-24' AND event_type = 'purchase'
GROUP BY device
ORDER BY device;
