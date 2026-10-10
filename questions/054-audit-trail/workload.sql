-- A day of changes to audit.products, as the application would make them.
-- 3 new products
INSERT INTO audit.products (product_id, name, price, stock) VALUES
  (100001, 'Trail Lantern', 39.00, 25),
  (100002, 'Canvas Tote', 18.50, 40),
  (100003, 'Enamel Mug', 12.00, 60);
-- a price rise on 40 products
UPDATE audit.products SET price = price + 1 WHERE product_id BETWEEN 1 AND 40;
-- an ORM that saves every row it loaded, changed or not
UPDATE audit.products SET price = price, name = name WHERE product_id BETWEEN 41 AND 60;
-- page views: only the counter moves
UPDATE audit.products SET view_count = view_count + 1 WHERE product_id BETWEEN 1 AND 100;
UPDATE audit.products SET view_count = view_count + 1 WHERE product_id BETWEEN 1 AND 100;
-- sales: the counter and the stock move together
UPDATE audit.products SET view_count = view_count + 1, stock = stock - 1 WHERE product_id BETWEEN 61 AND 65;
-- a bulk repricing that someone thought better of
BEGIN;
UPDATE audit.products SET price = 0 WHERE product_id BETWEEN 101 AND 150;
ROLLBACK;
-- two discontinued products
DELETE FROM audit.products WHERE product_id IN (199, 200);
-- end of season: someone clears the table
TRUNCATE audit.products;
