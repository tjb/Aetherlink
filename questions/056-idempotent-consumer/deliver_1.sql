-- The first hours of traffic: the broker delivers 60% of the messages to one consumer, out of
-- order, some of them twice. Now and then the consumer crashes before committing (ROLLBACK);
-- those messages will be delivered again later.
DO $$
DECLARE
  r record;
  n int := 0;
BEGIN
  FOR r IN
    SELECT p.seq, p.msg
    FROM inbox.published p
    CROSS JOIN LATERAL generate_series(1, CASE WHEN abs(hashint4(p.seq * 31)) % 5 = 0 THEN 2 ELSE 1 END) AS copy
    WHERE p.seq % 10 < 6
    ORDER BY hashint4(p.seq * 7 + copy)
  LOOP
    n := n + 1;
    PERFORM inbox.handle(r.msg);
    IF n % 37 = 0 THEN
      ROLLBACK;  -- crashed before the commit: nothing happened
    ELSE
      COMMIT;
    END IF;
  END LOOP;
END $$;
