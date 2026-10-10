-- Q025 · Prices as of a date
--
-- product_prices is a "type 2 slowly changing dimension": one row per version, with a
-- validity interval. Point-in-time lookups use the same half-open predicate as Q021.
--
-- The LATERAL ... ORDER BY valid_from DESC LIMIT 1 form needs only valid_from, and with an
-- index on (product_id, valid_from) (the primary key here!) it's one index probe per product.
WITH quarters AS (
  SELECT q AS quarter_start
  FROM generate_series(timestamptz '2025-01-01', timestamptz '2025-10-01', interval '3 months') AS q
)
SELECT q.quarter_start::date AS quarter_start,
       top.name              AS top_category,
       count(*)              AS products,
       round(avg(pp.price), 2) AS avg_price
FROM quarters q
JOIN product_prices pp
  ON pp.valid_from <= q.quarter_start
 AND (pp.valid_to IS NULL OR pp.valid_to > q.quarter_start)
JOIN products p      ON p.product_id = pp.product_id
JOIN categories leaf ON leaf.category_id = p.category_id
JOIN categories mid  ON mid.category_id = leaf.parent_id
JOIN categories top  ON top.category_id = mid.parent_id
GROUP BY q.quarter_start, top.name
ORDER BY q.quarter_start, top.name;
