-- Lab for Q055: order lines (with some history already in them) and the rollup to keep in sync.
DROP SCHEMA IF EXISTS rollup CASCADE;
CREATE SCHEMA rollup;

CREATE TABLE rollup.order_items (
  item_id    bigserial PRIMARY KEY,
  order_id   bigint NOT NULL,
  product_id int NOT NULL,
  quantity   int NOT NULL CHECK (quantity > 0),
  unit_price numeric(10,2) NOT NULL
);
INSERT INTO rollup.order_items (order_id, product_id, quantity, unit_price)
SELECT order_id, product_id, quantity, unit_price
FROM order_items
WHERE order_id > (SELECT max(order_id) - 3000 FROM orders)
ORDER BY order_id, line_no;

CREATE TABLE rollup.product_sales (
  product_id int PRIMARY KEY,
  units      bigint NOT NULL,
  revenue    numeric(14,2) NOT NULL
);
