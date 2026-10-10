-- The payments service. The checker runs 4 of these at once (:worker is 1..4): 800 transfers
-- each between the same 12 wallets, every transfer its own transaction.
SELECT set_config('dojo.worker', :'worker', false);
DO $$
DECLARE
  w   int := current_setting('dojo.worker')::int;
  a   int;
  b   int;
  amt numeric(12,2);
  ok  boolean;
BEGIN
  FOR i IN 1..800 LOOP
    a := 1 + abs(hashint4(w * 100000 + i)) % 12;
    b := 1 + (a + abs(hashint4(w * 100000 + i + 50000)) % 11) % 12;  -- never the same as a
    amt := 1 + (abs(hashint4(w * 7919 + i)) % 6000) / 100.0;         -- 1.00 to 60.99
    ok := wallet.transfer(a, b, amt);
    INSERT INTO wallet.attempts VALUES (w, i, a, b, amt, ok);
    COMMIT;
  END LOOP;
END $$;
