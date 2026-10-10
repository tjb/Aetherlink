WITH runs AS (
  SELECT l.*, j.priority, j.worker AS job_worker
  FROM queue.work_log l JOIN queue.jobs j USING (job_id)
)
SELECT 'every job is done' AS check,
       count(*) FILTER (WHERE status <> 'done') = 0 AS ok,
       format('%s queued, %s running, %s done', count(*) FILTER (WHERE status = 'queued'),
              count(*) FILTER (WHERE status = 'running'), count(*) FILTER (WHERE status = 'done')) AS detail
FROM queue.jobs
UNION ALL
SELECT 'no job was processed twice',
       count(*) = count(DISTINCT job_id),
       format('%s runs for %s distinct jobs', count(*), count(DISTINCT job_id))
FROM queue.work_log
UNION ALL
SELECT 'each job records the worker that claimed it',
       count(*) > 0 AND count(*) FILTER (WHERE job_worker IS DISTINCT FROM worker) = 0,
       format('%s of %s runs: the job names another worker (or none)',
              count(*) FILTER (WHERE job_worker IS DISTINCT FROM worker), count(*))
FROM runs
UNION ALL
SELECT 'urgent jobs (priority 10) ran before the others',
       max(started_at) FILTER (WHERE priority = 10) < min(finished_at) FILTER (WHERE priority = 0),
       format('%s normal jobs had finished before the last urgent job started',
              count(*) FILTER (WHERE priority = 0 AND finished_at <
                               (SELECT max(started_at) FROM runs WHERE priority = 10)))
FROM runs
UNION ALL
SELECT 'the 4 workers ran in parallel (not waiting on each other)',
       coalesce(busy >= 1.5, false),
       format('on average %s jobs in progress at once (4 would be perfect, 1 means one at a time)',
              coalesce(round(busy, 1), 0))
FROM (SELECT extract(epoch FROM sum(finished_at - started_at))
             / nullif(extract(epoch FROM max(finished_at) - min(started_at)), 0) AS busy
      FROM queue.work_log) b;
