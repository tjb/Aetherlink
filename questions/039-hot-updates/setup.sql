-- Lab for Q039: a densely packed counters table with an index on the hot column.
CREATE SCHEMA IF NOT EXISTS lab;
DROP TABLE IF EXISTS lab.product_stats;
CREATE TABLE lab.product_stats (
  product_id int PRIMARY KEY,
  views      bigint NOT NULL DEFAULT 0,
  carts      bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT '2026-01-01'
) WITH (fillfactor = 100, autovacuum_enabled = false);

INSERT INTO lab.product_stats (product_id, views, carts)
SELECT p.product_id,
       count(e.event_id) FILTER (WHERE e.event_type = 'product_view'),
       count(e.event_id) FILTER (WHERE e.event_type = 'add_to_cart')
FROM products p
LEFT JOIN events e ON e.product_id = p.product_id AND e.occurred_at >= '2025-12-01'
GROUP BY p.product_id
ORDER BY p.product_id;

-- someone added this "just in case" a long time ago
CREATE INDEX product_stats_views_idx ON lab.product_stats (views);
-- the dashboard really uses this one
CREATE INDEX product_stats_updated_idx ON lab.product_stats (updated_at);
VACUUM ANALYZE lab.product_stats;
