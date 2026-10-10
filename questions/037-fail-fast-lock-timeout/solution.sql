-- Q037 · Fail fast with lock_timeout
--
-- The lock queue is first-come, first-served: once an ACCESS EXCLUSIVE request is waiting,
-- later requests that conflict with *it* (all of them) line up behind it, even though they
-- don't conflict with the transaction actually holding the lock. One idle-in-transaction
-- session + one migration = an outage.
--
-- Defences, from cheapest to most thorough:
--   * lock_timeout on the migration role: the DDL gives up after 3s instead of queueing
--     forever. Retry later or with backoff.
--   * statement_timeout: a runaway statement can't hold its locks for hours.
--   * idle_in_transaction_session_timeout (for app roles): kills the forgotten open
--     transaction from step 1 that started all this.
--   * Lock-friendly DDL: CREATE INDEX CONCURRENTLY, ADD CONSTRAINT ... NOT VALID then
--     VALIDATE CONSTRAINT, and adding columns without a volatile default all avoid long
--     ACCESS EXCLUSIVE locks.
--
-- Role settings apply at the start of every new session of that role. Check them with \drds
-- or pg_db_role_setting. A session can still override them with SET.
ALTER ROLE app_migrator SET lock_timeout = '3s';
ALTER ROLE app_migrator SET statement_timeout = '10min';

-- Inspect the queue while it happens (from another session):
-- SELECT pid, pg_blocking_pids(pid) AS blocked_by, wait_event_type, state, left(query, 60)
-- FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid();
