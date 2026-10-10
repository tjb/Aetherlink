-- The original (slow) query from the question. Used to compute the expected result.
SELECT date_trunc('month', occurred_at)::date AS month,
       count(DISTINCT user_id)                AS monthly_active_users
FROM events
WHERE user_id IS NOT NULL
GROUP BY 1
ORDER BY 1;
