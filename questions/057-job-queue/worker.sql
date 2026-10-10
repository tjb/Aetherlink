-- A worker process. The checker runs 4 of these at once (:worker is 1..4).
-- Each job is claimed, worked on and marked done in ONE transaction: if the worker dies, its
-- transaction rolls back and the job is simply queued again.
SELECT set_config('dojo.worker', 'worker-' || :'worker', false);
DO $$
DECLARE
  me  text := current_setting('dojo.worker');
  job bigint;
  t0  timestamptz;
BEGIN
  LOOP
    job := queue.claim_job(me);
    EXIT WHEN job IS NULL;
    t0 := clock_timestamp();
    PERFORM pg_sleep(0.005);  -- the actual work: send the email, call the fraud API...
    INSERT INTO queue.work_log VALUES (job, me, t0, clock_timestamp());
    UPDATE queue.jobs SET status = 'done', done_at = clock_timestamp() WHERE job_id = job;
    COMMIT;
  END LOOP;
  COMMIT;
END $$;
