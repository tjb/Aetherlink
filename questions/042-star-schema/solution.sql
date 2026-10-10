-- Q042 · Build a star schema
--
-- Dimensional modelling (Kimball) in one paragraph: facts are events you measure (an order
-- line: quantity, revenue), dimensions are the context you slice by (when, what, who).
-- Facts are long and narrow, with keys and additive numbers. Dimensions are short and wide,
-- with descriptive text, hierarchies flattened (leaf/mid/top category), and NULLs replaced by
-- explicit labels so GROUP BY output reads well.
--
-- The grain ("one row per order line") is the most important decision. Everything in the fact
-- must be true at that grain. An order-level number (shipping cost, order total) belongs in an
-- order-grain fact, or must be allocated across lines, otherwise SUM() double counts. That's
-- the fan-out trap from Q001, solved once in the model instead of in every query.
--
-- Keys: here the natural ids double as dimension keys. Real warehouses often use surrogate keys
-- (a sequence per dimension), which become essential once dimensions keep history (Q044).
--
-- Rebuild strategy: drop and recreate is simple and idempotent. To avoid analysts seeing missing
-- tables mid-rebuild, build into a staging schema and swap with ALTER SCHEMA ... RENAME (or do
-- it all in one transaction, as below. DDL is transactional in Postgres).
BEGIN;
DROP SCHEMA IF EXISTS mart CASCADE;
CREATE SCHEMA mart;

CREATE TABLE mart.dim_date AS
SELECT to_char(d, 'YYYYMMDD')::int        AS date_key,
       d::date                            AS date,
       extract(year FROM d)::int          AS year,
       extract(quarter FROM d)::int       AS quarter,
       extract(month FROM d)::int         AS month,
       to_char(d, 'FMMonth')              AS month_name,
       extract(week FROM d)::int          AS iso_week,
       extract(isodow FROM d)::int        AS day_of_week,
       extract(isodow FROM d) IN (6, 7)   AS is_weekend
FROM generate_series(date '2023-01-01', date '2025-12-31', interval '1 day') AS d;
ALTER TABLE mart.dim_date ADD PRIMARY KEY (date_key);

CREATE TABLE mart.dim_product AS
SELECT p.product_id AS product_key, p.name AS product_name, p.brand,
       leaf.name AS leaf_category, mid.name AS mid_category, top.name AS top_category,
       p.price AS current_price
FROM products p
JOIN categories leaf ON leaf.category_id = p.category_id
JOIN categories mid  ON mid.category_id = leaf.parent_id
JOIN categories top  ON top.category_id = mid.parent_id;
ALTER TABLE mart.dim_product ADD PRIMARY KEY (product_key);

CREATE TABLE mart.dim_customer AS
SELECT user_id AS customer_key, country, signup_at::date AS signup_date,
       coalesce(referral_source, 'unknown') AS referral_source, is_test
FROM users;
ALTER TABLE mart.dim_customer ADD PRIMARY KEY (customer_key);

CREATE TABLE mart.fact_sales AS
SELECT oi.order_id, oi.line_no,
       to_char(o.created_at, 'YYYYMMDD')::int AS date_key,
       oi.product_id AS product_key,
       o.user_id     AS customer_key,
       o.device, o.status, oi.quantity, oi.unit_price,
       oi.quantity * oi.unit_price AS revenue
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id;
ALTER TABLE mart.fact_sales ADD PRIMARY KEY (order_id, line_no);
COMMIT;

-- Now analysts write:
--   SELECT d.year, p.top_category, sum(f.revenue)
--   FROM mart.fact_sales f JOIN mart.dim_date d USING (date_key) JOIN mart.dim_product p USING (product_key)
--   WHERE f.status NOT IN ('cancelled', 'returned') GROUP BY 1, 2;
