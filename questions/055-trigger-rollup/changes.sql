-- Back office, later that day.
-- support fixes lines that were booked to the wrong product
UPDATE rollup.order_items SET product_id = product_id + 1 WHERE item_id % 97 = 0;
-- a price correction on one product
UPDATE rollup.order_items SET unit_price = round(unit_price * 0.9, 2) WHERE product_id = 3;
-- an ORM saves lines it didn't change
UPDATE rollup.order_items SET quantity = quantity WHERE item_id % 11 = 0;
-- a marketplace partner's orders, imported in one statement
INSERT INTO rollup.order_items (order_id, product_id, quantity, unit_price)
SELECT 800000000 + order_id, product_id, quantity, unit_price
FROM order_items
WHERE order_id % 40 = 0
ORDER BY order_id, line_no
LIMIT 20000;
-- old cancelled orders are purged
DELETE FROM rollup.order_items WHERE order_id < 800000000 AND order_id % 13 = 0;
