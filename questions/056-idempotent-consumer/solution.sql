-- Q056 · An idempotent consumer
--
-- Message brokers (Kafka, SQS, RabbitMQ, Pub/Sub...) deliver "at least once": after a crash,
-- a timeout or a rebalance, messages come again, and rarely in the order they were sent.
-- "Exactly once" is something the consumer builds, with two tools:
--
-- 1. An inbox (dedupe table). Record the message id in the SAME transaction as its effects.
--    INSERT ... ON CONFLICT DO NOTHING is the check and the claim in one atomic step: if four
--    consumers get the same message at the same moment, one inserts the id, the other three
--    wait on the unique index until it commits, then see the conflict and skip.
--    The tempting version, "IF EXISTS (SELECT ... id) THEN RETURN", is a race: all four see
--    "not there yet", all four apply the message.
--
-- 2. Versions. Applying the same "status is now X" twice is harmless; applying an OLD status
--    after a newer one is not. So state updates carry a version (or a timestamp), and the write
--    only goes ahead when it's newer: ON CONFLICT ... DO UPDATE ... WHERE stored.version < new.
--    Deltas ("+1 order, +$40") are the opposite: order doesn't matter (they commute), but
--    duplicates do, hence the inbox. Real systems usually need both.
--
-- The producer side is the "transactional outbox": the order service writes its message to an
-- outbox table in the same transaction as the order itself, and a relay (or Debezium reading
-- the WAL) publishes from there. Writing to the database and the broker separately loses or
-- invents messages whenever one of the two writes fails.
--
-- The inbox grows forever; in production you'd prune ids older than the broker's redelivery
-- window.
CREATE TABLE IF NOT EXISTS inbox.processed (
  message_id   text PRIMARY KEY,
  processed_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION inbox.handle(msg jsonb) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  sign int := CASE msg->>'type' WHEN 'order_placed' THEN 1
                                WHEN 'order_cancelled' THEN -1
                                WHEN 'order_returned' THEN -1
                                ELSE 0 END;
BEGIN
  INSERT INTO inbox.processed (message_id) VALUES (msg->>'message_id')
  ON CONFLICT (message_id) DO NOTHING;
  IF NOT FOUND THEN
    RETURN;  -- a duplicate: already applied
  END IF;

  INSERT INTO inbox.order_status AS s (order_id, status, version)
  VALUES ((msg->>'order_id')::bigint, msg->>'status', (msg->>'version')::int)
  ON CONFLICT (order_id) DO UPDATE
  SET status = EXCLUDED.status, version = EXCLUDED.version
  WHERE s.version < EXCLUDED.version;  -- a late, older message changes nothing

  IF sign <> 0 THEN
    INSERT INTO inbox.customer_totals AS c (user_id, orders, spent)
    VALUES ((msg->>'user_id')::bigint, sign, sign * (msg->>'amount')::numeric)
    ON CONFLICT (user_id) DO UPDATE
    SET orders = c.orders + EXCLUDED.orders, spent = c.spent + EXCLUDED.spent;
  END IF;
END $$;
