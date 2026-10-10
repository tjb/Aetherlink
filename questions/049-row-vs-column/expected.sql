-- The same question, answered from the raw CSV files (correct, just slow).
SELECT strftime(occurred_at, '%Y-%m') AS month,
       count(DISTINCT user_id) AS monthly_active_users
FROM read_csv('lake/raw/events/*/*.csv.gz', hive_partitioning = true)
WHERE user_id IS NOT NULL
GROUP BY 1
ORDER BY 1;
