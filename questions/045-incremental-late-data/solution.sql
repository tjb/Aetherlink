-- Q045 · Late-arriving data
--
-- Three ideas that run through every streaming and incremental system:
--
--  1. Incremental: process only what's new and fold it into the existing result. Additive
--     measures (counts, sums) fold with "+". Distinct counts and medians don't fold, which is
--     why you'd keep the underlying set (see Q032) or a mergeable sketch (HyperLogLog).
--
--  2. Late data: aggregate by *event* time (when it happened), not *arrival* time. A late event
--     updates an old day, so the target must be updatable: upsert, not append. Real systems also
--     pick a "watermark": how late is too late. Past it, either drop the event or reprocess.
--
--  3. Exactly-once = at-least-once delivery + idempotent processing. Retries are inevitable, so
--     each batch carries an id, and recording "batch N is done" happens in the SAME transaction
--     as applying it. Then a crash leaves either both or neither, and a retry is a no-op.
--     Here, a single statement (data-modifying CTE) makes that atomic.
CREATE TABLE IF NOT EXISTS stream.loaded_batches (
  batch_id  int PRIMARY KEY,
  loaded_at timestamptz NOT NULL DEFAULT now()
);

WITH new_batches AS (
  INSERT INTO stream.loaded_batches (batch_id)
  SELECT DISTINCT batch_id FROM stream.landing_events
  ON CONFLICT (batch_id) DO NOTHING
  RETURNING batch_id
)
INSERT INTO stream.daily_event_counts AS d (day, event_type, events)
SELECT occurred_at::date, event_type, count(*)
FROM stream.landing_events
WHERE batch_id IN (SELECT batch_id FROM new_batches)
GROUP BY 1, 2
ON CONFLICT (day, event_type) DO UPDATE SET events = d.events + EXCLUDED.events;
