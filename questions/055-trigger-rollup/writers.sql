-- The checkout service: run in 4 sessions at once. Each session sells the same dozen popular
-- products, one order line per transaction, and sometimes edits or removes a line it wrote.
SELECT set_config('dojo.worker', :'worker', false);
DO $$
DECLARE
  w    int := current_setting('dojo.worker')::int;
  base bigint := 900000000 + w * 1000000;
BEGIN
  FOR i IN 1..600 LOOP
    INSERT INTO rollup.order_items (order_id, product_id, quantity, unit_price)
    VALUES (base + i, 1 + (i * 7 + w) % 12, 1 + (i + w) % 3, 10 + i % 17);
    COMMIT;
    IF i % 4 = 0 THEN  -- the customer adds one more
      UPDATE rollup.order_items SET quantity = quantity + 1 WHERE order_id = base + i - 2;
      COMMIT;
    END IF;
    IF i % 10 = 0 THEN  -- an order is cancelled
      DELETE FROM rollup.order_items WHERE order_id = base + i - 5;
      COMMIT;
    END IF;
  END LOOP;
END $$;
