WITH truth AS (
  SELECT product_id, sum(quantity) AS units, sum(quantity * unit_price) AS revenue
  FROM rollup.order_items
  GROUP BY product_id
), j AS (
  SELECT product_id,
         coalesce(t.units, 0) AS units, coalesce(t.revenue, 0) AS revenue,
         coalesce(s.units, 0) AS got_units, coalesce(s.revenue, 0) AS got_revenue
  FROM truth t FULL JOIN rollup.product_sales s USING (product_id)
)
SELECT 'product_sales is still a table, kept up to date by triggers on order_items' AS check,
       (SELECT relkind = 'r' FROM pg_class WHERE oid = 'rollup.product_sales'::regclass)
       AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'rollup.order_items'::regclass AND NOT tgisinternal) AS ok,
       '' AS detail
UNION ALL
SELECT 'the 12 popular products survived 4 concurrent writers',
       count(*) FILTER (WHERE got_units <> units OR got_revenue <> revenue) = 0,
       coalesce(min(format('product %s: %s units / %s revenue, should be %s / %s',
                           product_id, got_units, got_revenue, units, revenue))
                FILTER (WHERE got_units <> units OR got_revenue <> revenue), '')
FROM j WHERE product_id BETWEEN 1 AND 12
UNION ALL
SELECT 'units are right for every product (history, moves, deletes, bulk import)',
       count(*) FILTER (WHERE got_units <> units) = 0,
       format('%s of %s products wrong', count(*) FILTER (WHERE got_units <> units), count(*))
       || coalesce(', e.g. ' || min(format('product %s: %s, should be %s', product_id, got_units, units))
                                FILTER (WHERE got_units <> units), '')
FROM j
UNION ALL
SELECT 'revenue is right for every product',
       count(*) FILTER (WHERE got_revenue <> revenue) = 0,
       format('%s of %s products wrong', count(*) FILTER (WHERE got_revenue <> revenue), count(*))
       || coalesce(', e.g. ' || min(format('product %s: %s, should be %s', product_id, got_revenue, revenue))
                                FILTER (WHERE got_revenue <> revenue), '')
FROM j;
