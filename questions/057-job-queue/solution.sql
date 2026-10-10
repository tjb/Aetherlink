-- Q057 · A job queue with SKIP LOCKED
--
-- The three ways to get this wrong:
--  * No lock: "SELECT the first queued job, then UPDATE it". Two workers read the same row
--    before either updates it, and both run the job (the email goes out twice).
--  * UPDATE ... WHERE job_id = (SELECT ... LIMIT 1): the subquery is evaluated before the row
--    lock; a second worker blocks on the lock, then updates the same row anyway once the first
--    commits. Same double run.
--  * FOR UPDATE without SKIP LOCKED: correct, but every worker queues up behind the lock on the
--    first job, and four workers do the work of one.
--
-- FOR UPDATE SKIP LOCKED is made for this: "lock the first row nobody else has locked". Each
-- worker gets a different job at once, without waiting. Holding the row lock for the whole job
-- is a lease: if the worker dies, its transaction rolls back and the job is free again.
-- (A real queue would add attempts, a dead-letter status for jobs that keep failing, and, for
-- long jobs, a "running" status committed up front plus a visibility timeout, so you don't
-- hold a transaction open for minutes: long transactions block vacuum.)
--
-- Postgres as a queue is a fine choice at thousands of jobs a second (pgmq, River, Oban,
-- Solid Queue, graphile-worker all work like this), and the job commits with your data. Past
-- that, a broker. With many dead rows piling up, keep a partial index on the queued jobs.
CREATE INDEX IF NOT EXISTS jobs_queued ON queue.jobs (priority DESC, job_id) WHERE status = 'queued';

CREATE OR REPLACE FUNCTION queue.claim_job(p_worker text) RETURNS bigint
LANGUAGE sql AS $$
  UPDATE queue.jobs
  SET status = 'running', worker = p_worker, claimed_at = clock_timestamp()
  WHERE job_id = (
    SELECT job_id
    FROM queue.jobs
    WHERE status = 'queued'
    ORDER BY priority DESC, job_id
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING job_id;
$$;
