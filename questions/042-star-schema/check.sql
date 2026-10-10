WITH exp_date AS (
  SELECT to_char(d, 'YYYYMMDD')::int AS date_key, d::date AS date, extract(year FROM d)::int AS year,
         extract(quarter FROM d)::int AS quarter, extract(month FROM d)::int AS month,
         to_char(d, 'FMMonth') AS month_name, extract(week FROM d)::int AS iso_week,
         extract(isodow FROM d)::int AS day_of_week, extract(isodow FROM d) IN (6, 7) AS is_weekend
  FROM generate_series(date '2023-01-01', date '2025-12-31', interval '1 day') AS d
), got_date AS (
  SELECT date_key, date, year, quarter, month, month_name, iso_week, day_of_week, is_weekend FROM mart.dim_date
), exp_product AS (
  SELECT p.product_id AS product_key, p.name AS product_name, p.brand, leaf.name AS leaf_category,
         mid.name AS mid_category, top.name AS top_category, p.price AS current_price
  FROM products p
  JOIN categories leaf ON leaf.category_id = p.category_id
  JOIN categories mid  ON mid.category_id = leaf.parent_id
  JOIN categories top  ON top.category_id = mid.parent_id
), got_product AS (
  SELECT product_key, product_name, brand, leaf_category, mid_category, top_category, current_price FROM mart.dim_product
), exp_customer AS (
  SELECT user_id AS customer_key, country, signup_at::date AS signup_date,
         coalesce(referral_source, 'unknown') AS referral_source, is_test
  FROM users
), got_customer AS (
  SELECT customer_key, country, signup_date, referral_source, is_test FROM mart.dim_customer
), exp_fact AS (
  SELECT oi.order_id, oi.line_no, to_char(o.created_at, 'YYYYMMDD')::int AS date_key, oi.product_id AS product_key,
         o.user_id AS customer_key, o.device, o.status, oi.quantity, oi.unit_price, oi.quantity * oi.unit_price AS revenue
  FROM order_items oi JOIN orders o ON o.order_id = oi.order_id
), got_fact AS (
  SELECT order_id, line_no, date_key, product_key, customer_key, device, status, quantity, unit_price, revenue
  FROM mart.fact_sales
), diffs AS (
  SELECT 'dim_date' AS t, (SELECT count(*) FROM (SELECT * FROM exp_date EXCEPT ALL SELECT * FROM got_date) a)
                        + (SELECT count(*) FROM (SELECT * FROM got_date EXCEPT ALL SELECT * FROM exp_date) b) AS n,
         (SELECT count(*) FROM got_date) AS got, (SELECT count(*) FROM exp_date) AS exp
  UNION ALL
  SELECT 'dim_product', (SELECT count(*) FROM (SELECT * FROM exp_product EXCEPT ALL SELECT * FROM got_product) a)
                      + (SELECT count(*) FROM (SELECT * FROM got_product EXCEPT ALL SELECT * FROM exp_product) b),
         (SELECT count(*) FROM got_product), (SELECT count(*) FROM exp_product)
  UNION ALL
  SELECT 'dim_customer', (SELECT count(*) FROM (SELECT * FROM exp_customer EXCEPT ALL SELECT * FROM got_customer) a)
                       + (SELECT count(*) FROM (SELECT * FROM got_customer EXCEPT ALL SELECT * FROM exp_customer) b),
         (SELECT count(*) FROM got_customer), (SELECT count(*) FROM exp_customer)
  UNION ALL
  SELECT 'fact_sales', (SELECT count(*) FROM (SELECT * FROM exp_fact EXCEPT ALL SELECT * FROM got_fact) a)
                     + (SELECT count(*) FROM (SELECT * FROM got_fact EXCEPT ALL SELECT * FROM exp_fact) b),
         (SELECT count(*) FROM got_fact), (SELECT count(*) FROM exp_fact)
)
SELECT format('mart.%s matches the source', t) AS check, n = 0 AS ok,
       format('%s rows (expected %s), %s mismatched', got, exp, n) AS detail
FROM diffs
UNION ALL
SELECT 'every table has a primary key',
       count(*) FILTER (WHERE has_pk) = 4,
       'missing on: ' || coalesce(string_agg(t, ', ') FILTER (WHERE NOT has_pk), 'none')
FROM (SELECT t, EXISTS (SELECT 1 FROM pg_index WHERE indrelid = to_regclass('mart.' || t) AND indisprimary) AS has_pk
      FROM unnest(ARRAY['dim_date', 'dim_product', 'dim_customer', 'fact_sales']) t) k
UNION ALL
SELECT 'every fact row joins to all three dimensions',
       count(*) = 0, format('%s orphan fact rows', count(*))
FROM mart.fact_sales f
WHERE NOT EXISTS (SELECT 1 FROM mart.dim_date d WHERE d.date_key = f.date_key)
   OR NOT EXISTS (SELECT 1 FROM mart.dim_product p WHERE p.product_key = f.product_key)
   OR NOT EXISTS (SELECT 1 FROM mart.dim_customer c WHERE c.customer_key = f.customer_key)
