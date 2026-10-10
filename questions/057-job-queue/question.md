---
id: 57
title: A job queue with SKIP LOCKED
level: 9
kind: pipeline
plan: setup, answer, answer, parallel:worker*4, check
topics: SELECT FOR UPDATE, SKIP LOCKED, row locks, queues in Postgres, race conditions
tables: queue.jobs, queue.work_log
---
Background jobs (receipt emails, fraud reviews) wait in **`queue.jobs`**. Four worker processes
take jobs from it at the same time. Each worker runs this loop, and all of it is already written
except the function it calls:

```
loop:
  job := queue.claim_job('worker-N')     -- NULL when the queue is empty: stop
  ...do the work (5 ms)...
  log it in queue.work_log, set the job's status to 'done', COMMIT
```

The claim, the work and the "done" are **one transaction**, so a crashed worker's job goes
back in the queue on its own.

**Write `queue.claim_job(p_worker text) RETURNS bigint`.** It picks the next job and marks it
`running`, with `worker` = `p_worker` and `claimed_at` = now. Then:
- **No job runs twice**, and every job runs.
- **Highest `priority` first**, then oldest (`job_id`) first. The 100 urgent fraud reviews were
  queued last but must run first.
- The 4 workers must actually work **in parallel**: a worker never waits for another worker's
  job.

The checker runs your script twice, then the 4 workers until the queue is empty.

## Hints
- `SELECT ... ORDER BY priority DESC, job_id LIMIT 1` followed by an `UPDATE` is a race: two workers can read the same job before either updates it.
- `FOR UPDATE` on that SELECT fixes the race but makes every worker wait for the lock on the same first job: one job at a time. You want "the first job that **nobody** has locked".
- `UPDATE queue.jobs SET ... WHERE job_id = (SELECT job_id ... FOR UPDATE SKIP LOCKED) RETURNING job_id`, wrapped in a `LANGUAGE sql` function.
