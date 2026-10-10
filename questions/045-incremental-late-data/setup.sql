-- Lab for Q045: a landing table that only holds the newest batch, and the rollup to maintain.
DROP SCHEMA IF EXISTS stream CASCADE;
CREATE SCHEMA stream;

-- Which batch delivers each December event. Mostly by day, with stragglers arriving late.
CREATE FUNCTION stream.arrival_batch(event_id bigint, occurred_at timestamptz) RETURNS int
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN occurred_at < '2025-12-11' AND abs(hashint8extended(event_id, 451)) % 100 < 10 THEN 2
    WHEN occurred_at < '2025-12-21' AND abs(hashint8extended(event_id, 451)) % 100 >= 95 THEN 3
    WHEN occurred_at < '2025-12-11' THEN 1
    WHEN occurred_at < '2025-12-21' THEN 2
    ELSE 3 END
$$;

CREATE TABLE stream.landing_events (
  batch_id    int NOT NULL,
  event_id    bigint NOT NULL,
  occurred_at timestamptz NOT NULL,
  event_type  text NOT NULL
);

CREATE TABLE stream.daily_event_counts (
  day        date NOT NULL,
  event_type text NOT NULL,
  events     bigint NOT NULL,
  PRIMARY KEY (day, event_type)
);
