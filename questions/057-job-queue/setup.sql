-- Lab for Q057: a job queue in a table, and the workers' own record of what they did.
DROP SCHEMA IF EXISTS queue CASCADE;
CREATE SCHEMA queue;

CREATE TABLE queue.jobs (
  job_id     bigserial PRIMARY KEY,
  kind       text NOT NULL,
  priority   int NOT NULL DEFAULT 0,   -- higher runs first
  payload    jsonb NOT NULL,
  status     text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'running', 'done')),
  worker     text,
  claimed_at timestamptz,
  done_at    timestamptz
);
-- 900 receipt emails, then 100 urgent fraud reviews queued after them
INSERT INTO queue.jobs (kind, priority, payload)
SELECT 'send_receipt', 0, jsonb_build_object('order_id', order_id)
FROM (SELECT order_id FROM orders ORDER BY order_id DESC LIMIT 900) o
ORDER BY order_id;
INSERT INTO queue.jobs (kind, priority, payload)
SELECT 'fraud_review', 10, jsonb_build_object('order_id', order_id)
FROM (SELECT order_id FROM orders ORDER BY order_id DESC OFFSET 900 LIMIT 100) o
ORDER BY order_id;

-- Written by the workers (the checker), not by you.
CREATE TABLE queue.work_log (
  job_id      bigint NOT NULL,
  worker      text NOT NULL,
  started_at  timestamptz NOT NULL,
  finished_at timestamptz NOT NULL
);
