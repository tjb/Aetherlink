-- Lab for Q043: the supplier's daily full-catalogue snapshots and our (empty) copy.
DROP SCHEMA IF EXISTS supplier CASCADE;
CREATE SCHEMA supplier;

-- The supplier's API: snapshot k (1, 2, 3) of their catalogue. Products come and go,
-- prices change, a few get renamed.
CREATE FUNCTION supplier.snapshot(k int)
RETURNS TABLE (sku text, name text, price numeric(10,2), extracted_at timestamptz)
LANGUAGE sql STABLE AS $$
  SELECT 'LK-' || p.product_id,
         p.name || CASE WHEN k >= 3 AND abs(hashint8extended(p.product_id, 431)) % 100 < 3
                        THEN ' (2026 edition)' ELSE '' END,
         round(p.price
               * CASE WHEN k >= 2 AND abs(hashint8extended(p.product_id, 432)) % 100 < 10 THEN 0.90 ELSE 1 END
               * CASE WHEN k >= 3 AND abs(hashint8extended(p.product_id, 433)) % 100 < 8 THEN 1.05 ELSE 1 END, 2),
         timestamptz '2026-01-01 06:00+00' + (k - 1) * interval '1 day'
  FROM products p
  WHERE p.product_id % 4 = 0
    -- each day a different ~8% of the catalogue is missing from the feed
    AND abs(hashint8extended(p.product_id, 430 + k * 7)) % 100 >= CASE k WHEN 1 THEN 10 ELSE 7 END
$$;

CREATE TABLE supplier.catalog_feed (
  sku          text PRIMARY KEY,
  name         text NOT NULL,
  price        numeric(10,2) NOT NULL,
  extracted_at timestamptz NOT NULL
);

CREATE TABLE supplier.catalog (
  sku            text PRIMARY KEY,
  name           text NOT NULL,
  price          numeric(10,2) NOT NULL,
  is_active      boolean NOT NULL,
  first_seen_at  timestamptz NOT NULL,
  updated_at     timestamptz NOT NULL,
  deactivated_at timestamptz
);
