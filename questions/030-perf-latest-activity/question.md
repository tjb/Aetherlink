---
id: 30
title: Latest activity per user
level: 5
topics: B-tree indexes, composite index order, LATERAL, EXPLAIN ANALYZE
tables: users, events
target_ms: 25
---
The support tool shows our first 100 customers (real users, earliest `signup_at` first, ties by `user_id`) with the time and type of each one's **most recent event** (latest `occurred_at`, ties by largest `event_id`). Users with no events get NULLs.

This is the current query. It's correct, but it joins and sorts *every* event to keep 100 rows:

```sql
SELECT DISTINCT ON (u.user_id)
       u.user_id,
       e.occurred_at AS last_event_at,
       e.event_type  AS last_event_type
FROM users u
LEFT JOIN events e ON e.user_id = u.user_id
WHERE u.user_id IN (SELECT user_id FROM users WHERE NOT is_test ORDER BY signup_at, user_id LIMIT 100)
ORDER BY u.user_id, e.occurred_at DESC, e.event_id DESC;
```

**Make it return the same result in under 25 ms.** You may create indexes (in `./dojo psql`). Your answer file must contain only the `SELECT`.

**Expected columns:** `user_id`, `last_event_at`, `last_event_type`. 100 rows.

## Hints
- Run `./dojo explain 30` on the original first. Where does the time go?
- For each user you want "the newest event of user X": one trip down a B-tree index on `(user_id, occurred_at DESC, event_id DESC)`, *if* the query asks for exactly that. `LEFT JOIN LATERAL (... ORDER BY ... LIMIT 1) ON true` does.
- The 100 users are chosen by `signup_at`. That needs an index too, or a full scan of `users`.
- Equality columns first, then range/sort columns: the order of columns in a composite index decides which queries it can serve.
