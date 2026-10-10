WITH log AS (
  SELECT * FROM audit.product_log
), upd AS (
  SELECT product_id, count(*) AS n FROM log WHERE op = 'UPDATE' GROUP BY product_id
)
SELECT 'the 3 inserts are logged, with new_row and no old_row' AS check,
       count(*) = 3 AND bool_and(old_row IS NULL AND new_row->>'name' IS NOT NULL
                                 AND (new_row->>'product_id')::int = product_id) AS ok,
       format('%s INSERT entries', count(*)) AS detail
FROM log WHERE op = 'INSERT'
UNION ALL
SELECT 'each of the 40 price changes is logged once, with the old and new price',
       (SELECT count(*) FROM upd WHERE product_id BETWEEN 1 AND 40 AND n = 1) = 40
       AND (SELECT count(*) FROM log l JOIN products p USING (product_id)
            WHERE l.op = 'UPDATE' AND l.product_id BETWEEN 1 AND 40
              AND (l.old_row->>'price')::numeric = p.price
              AND (l.new_row->>'price')::numeric = p.price + 1) = 40,
       format('%s of 40 products logged exactly once; %s entries show the price going from p to p + 1',
              (SELECT count(*) FROM upd WHERE product_id BETWEEN 1 AND 40 AND n = 1),
              (SELECT count(*) FROM log l JOIN products p USING (product_id)
               WHERE l.op = 'UPDATE' AND l.product_id BETWEEN 1 AND 40
                 AND (l.old_row->>'price')::numeric = p.price
                 AND (l.new_row->>'price')::numeric = p.price + 1))
UNION ALL
SELECT 'updates that change nothing are not logged',
       NOT EXISTS (SELECT 1 FROM upd WHERE product_id BETWEEN 41 AND 60),
       format('%s entries for products 41-60', (SELECT coalesce(sum(n), 0) FROM upd WHERE product_id BETWEEN 41 AND 60))
UNION ALL
SELECT 'updates that only bump view_count are not logged',
       NOT EXISTS (SELECT 1 FROM log WHERE op = 'UPDATE' AND old_row - 'view_count' = new_row - 'view_count'),
       format('%s view-count-only entries',
              (SELECT count(*) FROM log WHERE op = 'UPDATE' AND old_row - 'view_count' = new_row - 'view_count'))
UNION ALL
SELECT 'the 5 stock changes are logged (even though view_count moved too)',
       (SELECT count(*) FROM upd WHERE product_id BETWEEN 61 AND 65 AND n = 1) = 5,
       format('%s of 5 logged exactly once', (SELECT count(*) FROM upd WHERE product_id BETWEEN 61 AND 65 AND n = 1))
UNION ALL
SELECT 'nothing from the rolled-back transaction',
       NOT EXISTS (SELECT 1 FROM log WHERE product_id BETWEEN 101 AND 150),
       format('%s entries for products 101-150', (SELECT count(*) FROM log WHERE product_id BETWEEN 101 AND 150))
UNION ALL
SELECT 'the 2 deletes are logged, with old_row and no new_row',
       count(*) = 2 AND bool_and(new_row IS NULL AND (old_row->>'product_id')::int = product_id
                                 AND product_id IN (199, 200)),
       format('%s DELETE entries', count(*))
FROM log WHERE op = 'DELETE'
UNION ALL
SELECT 'the TRUNCATE is logged (once)',
       count(*) = 1,
       format('%s TRUNCATE entries', count(*))
FROM log WHERE op = 'TRUNCATE'
UNION ALL
SELECT 'nothing else is logged',
       count(*) = 3 + 45 + 2 + 1,
       format('%s entries in total', count(*))
FROM log;
