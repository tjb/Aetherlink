-- Q032 · Precompute monthly actives
--
-- Setup (run once in ./dojo psql):
--   CREATE MATERIALIZED VIEW monthly_active_users AS
--   SELECT date_trunc('month', occurred_at)::date AS month,
--          count(DISTINCT user_id)                AS monthly_active_users
--   FROM events
--   WHERE user_id IS NOT NULL
--   GROUP BY 1;
--   CREATE UNIQUE INDEX ON monthly_active_users (month);   -- enables REFRESH ... CONCURRENTLY
--
-- Nightly: REFRESH MATERIALIZED VIEW CONCURRENTLY monthly_active_users;
--
-- Why not precompute *daily* active users and add them up? Distinct counts don't add: someone
-- active on 20 days of a month is one monthly user, not 20. Distinct counts aggregate up only
-- if you keep the underlying set, e.g. a (month, user_id) table, which you can maintain
-- incrementally (INSERT ... ON CONFLICT DO NOTHING for new days) instead of recomputing.
-- At real scale, HyperLogLog sketches (the postgresql-hll extension) trade a ~1% error for
-- tiny, mergeable summaries.
SELECT month, monthly_active_users
FROM monthly_active_users
ORDER BY month;
