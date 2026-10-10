-- A rebalance: the broker redelivers EVERYTHING, to 4 consumers at once, in publication order.
-- (Run in 4 concurrent sessions.)
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT msg FROM inbox.published ORDER BY seq LOOP
    PERFORM inbox.handle(r.msg);
    COMMIT;
  END LOOP;
END $$;
