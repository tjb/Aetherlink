---
id: 42
title: Build a star schema
level: 7
kind: pipeline
plan: setup, answer, answer, check
topics: dimensional modeling, facts and dimensions, grain, surrogate keys, date dimensions
tables: orders, order_items, products, categories, users
---
Analysts keep re-deriving the same joins (the category tree, revenue, dates) and getting them
slightly wrong. Give them a **star schema** in the schema `mart`: one fact table at a clear grain,
surrounded by dimensions they can join to.

Your load script must (re)build these four tables from the source tables. It runs twice in a row,
so it has to be repeatable.

**`mart.dim_date`**: one row per day from 2023-01-01 to 2025-12-31.
`date_key` (int, `yyyymmdd`, primary key), `date`, `year`, `quarter`, `month`, `month_name`
(`January`, ...), `iso_week`, `day_of_week` (ISO: Monday = 1 ... Sunday = 7), `is_weekend`.

**`mart.dim_product`**: one row per product.
`product_key` (= `product_id`, primary key), `product_name`, `brand`, `leaf_category`,
`mid_category`, `top_category` (category *names*, walking up the tree), `current_price`.

**`mart.dim_customer`**: one row per user.
`customer_key` (= `user_id`, primary key), `country`, `signup_date` (UTC date), `referral_source`
(NULL becomes `'unknown'`), `is_test`.

**`mart.fact_sales`**: **one row per order line** (the grain), for every order, whatever its status.
`order_id`, `line_no` (primary key on both), `date_key` (the UTC order date), `product_key`,
`customer_key`, `device`, `status`, `quantity`, `unit_price`, `revenue` (`quantity * unit_price`).

Declare the primary keys. The checker compares every table with the source and verifies that
every fact row joins to all three dimensions.

## Hints
- `CREATE SCHEMA IF NOT EXISTS mart;` then `DROP TABLE IF EXISTS ...` / `CREATE TABLE ... AS SELECT` (and `ALTER TABLE ... ADD PRIMARY KEY`) is the simplest repeatable full rebuild.
- `dim_date`: `generate_series(date '2023-01-01', date '2025-12-31', interval '1 day')`, plus `extract(isodow ...)`, `extract(week ...)` and `to_char(d, 'FMMonth')`. The `FM` prefix drops the padding.
- Decide the grain first and write it down. Every number in a fact table must be additive at that grain. (`revenue` is. An order total repeated on every line would not be.)
