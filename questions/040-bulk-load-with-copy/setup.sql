-- Lab for Q040: writes a messy partner CSV on the database server and creates the target table.
DROP SCHEMA IF EXISTS partner CASCADE;
CREATE SCHEMA partner;

CREATE TABLE partner.orders (
  order_id       bigint PRIMARY KEY,
  ordered_at     timestamptz NOT NULL,
  customer_email text NOT NULL,
  country        char(2),
  units          int NOT NULL,
  total          numeric(12,2) NOT NULL,
  status         text NOT NULL,
  notes          text
);

-- The export: EU orders from December 2025, formatted the way the partner's system does it.
CREATE TEMP TABLE export AS
SELECT o.order_id,
       to_char(o.created_at AT TIME ZONE 'Europe/Berlin', 'DD/MM/YYYY HH24:MI') AS "Order Date",
       u.email AS "Customer Email",
       CASE WHEN abs(hashint8extended(o.order_id, 401)) % 100 < 5 THEN NULL ELSE u.country END AS "Country",
       t.units AS "Units",
       to_char(t.total, 'FM999,999,990.00') AS "Total (USD)",
       CASE abs(hashint8extended(o.order_id, 402)) % 10
         WHEN 0 THEN upper(o.status) WHEN 1 THEN upper(o.status)
         WHEN 2 THEN initcap(o.status) WHEN 3 THEN ' ' || o.status || ' '
         ELSE o.status END AS "Status",
       CASE abs(hashint8extended(o.order_id, 403)) % 20
         WHEN 0 THEN 'Gift wrap, please'
         WHEN 1 THEN 'Leave at the "back" door'
         WHEN 2 THEN 'Call before delivery; gate code 1234'
         WHEN 3 THEN 'Fragile!'
         ELSE NULL END AS "Notes"
FROM orders o
JOIN users u ON u.user_id = o.user_id
JOIN (SELECT order_id, sum(quantity) AS units, sum(quantity * unit_price) AS total
      FROM order_items GROUP BY order_id) t ON t.order_id = o.order_id
WHERE o.created_at >= '2025-12-01' AND o.created_at < '2026-01-01'
  AND o.ship_country IN ('DE', 'FR', 'NL', 'ES');

COPY (
  SELECT order_id AS "Order ID", "Order Date", "Customer Email", "Country", "Units", "Total (USD)", "Status", "Notes"
  FROM (
    SELECT *, 1 AS copy_no FROM export
    UNION ALL  -- the partner's system exports some orders twice
    SELECT *, 2 FROM export WHERE abs(hashint8extended(order_id, 404)) % 100 < 3
  ) e
  ORDER BY copy_no, order_id
) TO '/tmp/dojo_partner_orders.csv' WITH (FORMAT csv, HEADER true);

DROP TABLE export;
