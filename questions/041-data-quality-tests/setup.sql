-- Lab for Q041: an unconstrained extract with planted data-quality problems.
DROP SCHEMA IF EXISTS dq CASCADE;
CREATE SCHEMA dq;

CREATE TABLE dq.orders_snapshot AS
SELECT o.order_id, o.user_id, o.created_at, o.shipped_at, o.status, t.amount
FROM orders o
JOIN (SELECT order_id, sum(quantity * unit_price) AS amount FROM order_items GROUP BY order_id) t
  ON t.order_id = o.order_id
WHERE o.created_at >= '2025-10-01';

-- Plant problems. Deterministic, keyed on the original order_id.
INSERT INTO dq.orders_snapshot                          -- re-delivered rows
SELECT * FROM dq.orders_snapshot WHERE abs(hashint8extended(order_id, 411)) % 1000 < 4;
UPDATE dq.orders_snapshot SET user_id = user_id + 50000000   -- users that don't exist
WHERE abs(hashint8extended(order_id, 412)) % 1000 < 3;
UPDATE dq.orders_snapshot                               -- statuses from a newer app version
SET status = CASE abs(hashint8extended(order_id, 413)) % 3 WHEN 0 THEN 'Delivered' WHEN 1 THEN 'lost' ELSE NULL END
WHERE abs(hashint8extended(order_id, 414)) % 1000 < 5;
UPDATE dq.orders_snapshot                               -- currency bugs
SET amount = CASE abs(hashint8extended(order_id, 415)) % 3 WHEN 0 THEN -amount WHEN 1 THEN amount * 100 ELSE NULL END
WHERE abs(hashint8extended(order_id, 416)) % 1000 < 4;
UPDATE dq.orders_snapshot SET shipped_at = created_at - interval '3 hours'  -- clock skew
WHERE shipped_at IS NOT NULL AND abs(hashint8extended(order_id, 417)) % 1000 < 3;
UPDATE dq.orders_snapshot SET created_at = created_at + interval '400 days'  -- bad timezone math
WHERE abs(hashint8extended(order_id, 418)) % 1000 < 2;
UPDATE dq.orders_snapshot SET order_id = NULL           -- lost keys
WHERE abs(hashint8extended(order_id, 419)) % 1000 < 2;
