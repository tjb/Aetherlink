-- The original (slow) query from the question. Used to compute the expected result.
SELECT DISTINCT ON (u.user_id)
       u.user_id,
       e.occurred_at AS last_event_at,
       e.event_type  AS last_event_type
FROM users u
LEFT JOIN events e ON e.user_id = u.user_id
WHERE u.user_id IN (SELECT user_id FROM users WHERE NOT is_test ORDER BY signup_at, user_id LIMIT 100)
ORDER BY u.user_id, e.occurred_at DESC, e.event_id DESC;
