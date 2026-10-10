-- Q055 · A rollup that keeps itself up to date
--
-- Three things to get right:
--
-- 1. Every kind of change. An UPDATE is "remove the old line, add the new one": that handles a
--    quantity change, a price change and a line moved to another product with the same code.
--
-- 2. Concurrency. Four sessions bump the same dozen counters. The classic bug is
--    read-modify-write in two steps:
--        SELECT units INTO u ...;  UPDATE ... SET units = u + n;     -- loses updates
--    Two sessions read the same u, and one increment vanishes. A single statement,
--    "SET units = units + n" (or INSERT ... ON CONFLICT DO UPDATE), is safe in READ COMMITTED:
--    the UPDATE takes the row lock, and if another transaction changed the row meanwhile,
--    Postgres re-reads the latest version before applying "+ n".
--    The other classic bug: "IF NOT FOUND THEN INSERT" races with another session inserting
--    the same product (unique violation). ON CONFLICT handles both.
--
-- 3. The backfill. The history must be counted once, and rerunning the script must not count
--    it twice: recompute from scratch inside one transaction. Lock the table first, otherwise a
--    line written between "create the trigger" and "backfill" is counted twice or not at all.
--
-- These are statement-level triggers with transition tables: one upsert per statement instead
-- of one per row, which matters for the 20,000-line import. ORDER BY product_id makes every
-- statement lock counters in the same order, so two multi-row statements can't deadlock.
-- Row-level triggers (AFTER INSERT OR UPDATE OR DELETE ... FOR EACH ROW, using OLD and NEW)
-- are simpler and pass this lab too.
--
-- The cost: every sale now waits for the lock on its product's counter, so a very hot product
-- serializes its writers. At high volume the usual fix is to append deltas to a table instead
-- and fold them into the totals every few seconds (exactly Q045's incremental load).
CREATE OR REPLACE FUNCTION rollup.apply_item_delta() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO rollup.product_sales AS s (product_id, units, revenue)
    SELECT product_id, sum(quantity), sum(quantity * unit_price)
    FROM new_rows GROUP BY product_id ORDER BY product_id
    ON CONFLICT (product_id) DO UPDATE
    SET units = s.units + EXCLUDED.units, revenue = s.revenue + EXCLUDED.revenue;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE rollup.product_sales AS s
    SET units = s.units - d.units, revenue = s.revenue - d.revenue
    FROM (SELECT product_id, sum(quantity) AS units, sum(quantity * unit_price) AS revenue
          FROM old_rows GROUP BY product_id ORDER BY product_id) d
    WHERE s.product_id = d.product_id;
  ELSE  -- UPDATE: take away the old lines, add the new ones
    INSERT INTO rollup.product_sales AS s (product_id, units, revenue)
    SELECT product_id, sum(units), sum(revenue)
    FROM (
      SELECT product_id, -quantity AS units, -quantity * unit_price AS revenue FROM old_rows
      UNION ALL
      SELECT product_id, quantity, quantity * unit_price FROM new_rows
    ) d
    GROUP BY product_id ORDER BY product_id
    ON CONFLICT (product_id) DO UPDATE
    SET units = s.units + EXCLUDED.units, revenue = s.revenue + EXCLUDED.revenue;
  END IF;
  RETURN NULL;
END $$;

BEGIN;
LOCK TABLE rollup.order_items IN SHARE ROW EXCLUSIVE MODE;  -- no writes while we switch over

-- a trigger with transition tables can only handle one kind of event
CREATE OR REPLACE TRIGGER items_sales_ins AFTER INSERT ON rollup.order_items
  REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT EXECUTE FUNCTION rollup.apply_item_delta();
CREATE OR REPLACE TRIGGER items_sales_upd AFTER UPDATE ON rollup.order_items
  REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
  FOR EACH STATEMENT EXECUTE FUNCTION rollup.apply_item_delta();
CREATE OR REPLACE TRIGGER items_sales_del AFTER DELETE ON rollup.order_items
  REFERENCING OLD TABLE AS old_rows
  FOR EACH STATEMENT EXECUTE FUNCTION rollup.apply_item_delta();

DELETE FROM rollup.product_sales;
INSERT INTO rollup.product_sales (product_id, units, revenue)
SELECT product_id, sum(quantity), sum(quantity * unit_price)
FROM rollup.order_items
GROUP BY product_id;
COMMIT;
