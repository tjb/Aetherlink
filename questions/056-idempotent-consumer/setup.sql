-- Lab for Q056: what the order service published, and the read models a consumer maintains.
DROP SCHEMA IF EXISTS inbox CASCADE;
CREATE SCHEMA inbox;

-- The read models you keep up to date.
CREATE TABLE inbox.order_status (
  order_id bigint PRIMARY KEY,
  status   text NOT NULL,
  version  int NOT NULL
);
CREATE TABLE inbox.customer_totals (
  user_id bigint PRIMARY KEY,
  orders  int NOT NULL,           -- orders that are neither cancelled nor returned
  spent   numeric(14,2) NOT NULL  -- what those orders cost
);

-- The broker's copy of every message, in publication order. The checker delivers from here.
CREATE TABLE inbox.published (
  seq int PRIMARY KEY,
  msg jsonb NOT NULL
);

WITH picked AS MATERIALIZED (  -- 1,200 orders from the second half of 2025
  SELECT order_id, user_id, status, created_at, shipped_at, delivered_at
  FROM orders
  WHERE created_at >= '2025-06-01'
  ORDER BY hashint8(order_id)
  LIMIT 1200
), o AS (
  SELECT p.*, (SELECT sum(quantity * unit_price) FROM order_items i WHERE i.order_id = p.order_id) AS amount
  FROM picked p
), m AS (
  SELECT o.*, v.type, v.version, v.new_status, v.at
  FROM o
  CROSS JOIN LATERAL (VALUES
    ('order_placed',    1, 'pending',   created_at),
    ('order_shipped',   2, 'shipped',   shipped_at),
    ('order_delivered', 3, 'delivered', delivered_at),
    ('order_cancelled', 2, 'cancelled', CASE WHEN status = 'cancelled' THEN created_at + interval '2 hours' END),
    ('order_returned',  4, 'returned',  CASE WHEN status = 'returned' THEN delivered_at + interval '9 days' END)
  ) AS v(type, version, new_status, at)
  WHERE v.at IS NOT NULL
)
INSERT INTO inbox.published (seq, msg)
SELECT row_number() OVER (ORDER BY at, order_id, version),
       jsonb_build_object(
         'message_id', format('ord-%s-v%s', order_id, version),
         'type', type,
         'order_id', order_id,
         'user_id', user_id,
         'version', version,
         'status', new_status,
         'amount', CASE WHEN type IN ('order_placed', 'order_cancelled', 'order_returned') THEN amount END,
         'occurred_at', at)
FROM m;
