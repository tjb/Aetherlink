-- Simulate the sync rules over the three feeds to get the expected final state.
WITH RECURSIVE feeds AS (
  SELECT k, f.* FROM generate_series(1, 3) AS k CROSS JOIN LATERAL supplier.snapshot(k) AS f
), skus AS (
  SELECT DISTINCT sku FROM feeds
), sim AS (
  SELECT 0 AS k, sku, NULL::text AS name, NULL::numeric AS price, NULL::boolean AS is_active,
         NULL::timestamptz AS first_seen_at, NULL::timestamptz AS updated_at, NULL::timestamptz AS deactivated_at
  FROM skus
  UNION ALL
  SELECT s.k + 1, s.sku,
         coalesce(f.name, s.name),
         coalesce(f.price, s.price),
         CASE WHEN f.sku IS NOT NULL THEN true WHEN s.is_active THEN false ELSE s.is_active END,
         coalesce(s.first_seen_at, f.extracted_at),
         CASE WHEN f.sku IS NOT NULL AND (s.is_active IS DISTINCT FROM true
                                          OR (f.name, f.price) IS DISTINCT FROM (s.name, s.price))
                THEN f.extracted_at
              WHEN f.sku IS NULL AND s.is_active
                THEN timestamptz '2026-01-01 06:00+00' + s.k * interval '1 day'
              ELSE s.updated_at END,
         CASE WHEN f.sku IS NOT NULL THEN NULL
              WHEN s.is_active THEN timestamptz '2026-01-01 06:00+00' + s.k * interval '1 day'
              ELSE s.deactivated_at END
  FROM sim s
  LEFT JOIN feeds f ON f.k = s.k + 1 AND f.sku = s.sku
  WHERE s.k < 3
), expected AS (
  SELECT sku, name, price, is_active, first_seen_at, updated_at, deactivated_at
  FROM sim WHERE k = 3 AND first_seen_at IS NOT NULL
), j AS (
  SELECT e.*, c.sku AS c_sku, c.name AS c_name, c.price AS c_price, c.is_active AS c_active,
         c.first_seen_at AS c_first, c.updated_at AS c_updated, c.deactivated_at AS c_deact
  FROM expected e LEFT JOIN supplier.catalog c ON c.sku = e.sku
)
SELECT 'every SKU ever seen is in the catalog, once' AS check,
       (SELECT count(*) FROM supplier.catalog) = (SELECT count(*) FROM expected)
         AND count(*) FILTER (WHERE c_sku IS NULL) = 0 AS ok,
       format('%s rows, expected %s', (SELECT count(*) FROM supplier.catalog), (SELECT count(*) FROM expected)) AS detail
FROM j
UNION ALL
SELECT 'is_active matches the latest feed',
       count(*) FILTER (WHERE c_active IS DISTINCT FROM is_active) = 0,
       format('%s wrong', count(*) FILTER (WHERE c_active IS DISTINCT FROM is_active))
FROM j
UNION ALL
SELECT 'names and prices are the latest values sent',
       count(*) FILTER (WHERE (c_name, c_price) IS DISTINCT FROM (name, price)) = 0,
       coalesce(min(format('%s: expected %s / %s, got %s / %s', sku, name, price, c_name, c_price))
                FILTER (WHERE c_sku IS NOT NULL AND (c_name, c_price) IS DISTINCT FROM (name, price)), '')
FROM j
UNION ALL
SELECT 'first_seen_at is the first feed containing the SKU',
       count(*) FILTER (WHERE c_first IS DISTINCT FROM first_seen_at) = 0,
       format('%s wrong', count(*) FILTER (WHERE c_first IS DISTINCT FROM first_seen_at))
FROM j
UNION ALL
SELECT 'updated_at moves only when something actually changed',
       count(*) FILTER (WHERE c_updated IS DISTINCT FROM updated_at) = 0,
       coalesce(min(format('%s: expected %s, got %s', sku, updated_at, c_updated))
                FILTER (WHERE c_sku IS NOT NULL AND c_updated IS DISTINCT FROM updated_at), '')
FROM j
UNION ALL
SELECT 'deactivated_at is set on removal and cleared on return',
       count(*) FILTER (WHERE c_deact IS DISTINCT FROM deactivated_at) = 0,
       format('%s wrong', count(*) FILTER (WHERE c_deact IS DISTINCT FROM deactivated_at))
FROM j
