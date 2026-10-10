---
id: 32
title: Precompute monthly actives
level: 5
topics: materialized views, rollups, COUNT DISTINCT, pre-aggregation
tables: events
target_ms: 25
---
The exec dashboard shows monthly active users (MAU, distinct logged-in users with at least one event) for every month:

```sql
SELECT date_trunc('month', occurred_at)::date AS month,
       count(DISTINCT user_id)                AS monthly_active_users
FROM events
WHERE user_id IS NOT NULL
GROUP BY 1
ORDER BY 1;
```

It takes seconds and gets slower every day. The data only changes in a nightly batch, so it's fine to **precompute**. **Make the dashboard query return the same result in under 25 ms.** You may create any objects you like. Your answer file must contain only the `SELECT` the dashboard runs.

**Expected columns:** `month`, `monthly_active_users`. 36 rows.

## Hints
- No index makes `count(DISTINCT ...)` over millions of rows fast. You need to do less work at query time.
- `CREATE MATERIALIZED VIEW ... AS <query>` stores a query's result. Refresh it with `REFRESH MATERIALIZED VIEW`.
- Tempted to precompute *daily* active users and sum them? Try it and see what goes wrong.
