---
id: 37
title: Fail fast with lock_timeout
level: 6
kind: state
topics: locks, lock queues, lock_timeout, statement_timeout, role settings
tables: lab.import_batches, pg_locks, pg_stat_activity
---
`TRUNCATE`, `ALTER TABLE`, `DROP` and `VACUUM FULL` need an **ACCESS EXCLUSIVE** lock, which
conflicts with *everything*, plain `SELECT`s included. That makes a harmless-looking migration
dangerous:

1. A slow report has been reading `lab.import_batches` for 10 minutes (it holds a share lock).
2. The migration's `TRUNCATE lab.import_batches` queues behind it, waiting.
3. **Every new query on the table queues behind the waiting migration.** The app is down,
   and nothing is even running.

**See it for yourself** with three `./dojo psql` terminals:

```sql
-- terminal 1: the slow report
BEGIN; SELECT count(*) FROM lab.import_batches;        -- leave the transaction open
-- terminal 2: the migration (it hangs)
TRUNCATE lab.import_batches;
-- terminal 3: an innocent app query (it hangs too!)
SELECT * FROM lab.import_batches LIMIT 1;
-- terminal 1 again: who is waiting on whom?
SELECT pid, pg_blocking_pids(pid) AS blocked_by, wait_event_type, left(query, 50)
FROM pg_stat_activity WHERE datname = 'dojo' AND state <> 'idle';
COMMIT;                                                -- everything resumes
```

Then fix it the way production teams do: migrations should **give up quickly** instead of
queueing. **Configure the role `app_migrator` so that every session it opens waits at most
3 seconds for a lock, and aborts any single statement that runs longer than 10 minutes.**
(Set it once on the role. Don't rely on each migration remembering a `SET`.)

## Hints
- The two settings are `lock_timeout` and `statement_timeout`.
- `ALTER ROLE ... SET parameter = value` stores a default that's applied at every login of that role. You can see stored values in `pg_db_role_setting` (or `\drds` in psql).
- Retrying a migration that failed fast is cheap. An outage caused by a lock queue is not. Many teams retry with backoff: `SET lock_timeout = '3s'` + a loop in the migration tool.
