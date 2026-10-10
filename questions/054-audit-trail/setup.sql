-- Lab for Q054: a small copy of the catalogue, and the audit log to fill.
DROP SCHEMA IF EXISTS audit CASCADE;
CREATE SCHEMA audit;

CREATE TABLE audit.products (
  product_id int PRIMARY KEY,
  name       text NOT NULL,
  price      numeric(10,2) NOT NULL,
  stock      int NOT NULL,
  view_count bigint NOT NULL DEFAULT 0   -- bumped on every page view: noise, not a change
);
INSERT INTO audit.products (product_id, name, price, stock)
SELECT product_id, name, price, 10 + product_id % 90
FROM products
WHERE product_id <= 200;

CREATE TABLE audit.product_log (
  log_id     bigserial PRIMARY KEY,
  tx_id      xid8 NOT NULL DEFAULT pg_current_xact_id(),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by text NOT NULL DEFAULT current_user,
  op         text NOT NULL CHECK (op IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')),
  product_id int,
  old_row    jsonb,
  new_row    jsonb
);
