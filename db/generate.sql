-- =============================================================================
-- SQL Dojo dataset generator
--
-- Builds the "Larkspur" e-commerce warehouse entirely inside Postgres with
-- generate_series(). No external files, no Python, no network.
--
--   psql -v scale=1 -f db/generate.sql
--
-- scale=1 is ~5M events / ~80k orders / 100k users (~1 GB on disk). Everything grows linearly
-- with scale (products grow with sqrt(scale)).
--
-- The data is deterministic: every "random" value is a hash of a row key and a
-- salt (see _dojo.rnd), so the same scale always produces byte-identical data on
-- any machine, regardless of query plans or parallelism.
--
-- Reading this file is a lesson of its own: it leans heavily on
-- generate_series, LATERAL, window functions, CTEs and set-based thinking.
-- =============================================================================

\set ON_ERROR_STOP on
\if :{?scale}
\else
  \set scale 1
\endif

SET client_min_messages = warning;
SET timezone = 'UTC';
SET search_path = public;
SET work_mem = '256MB';
SET maintenance_work_mem = '1GB';
SET max_parallel_maintenance_workers = 4;

SELECT round(100000 * :scale)::bigint                     AS n_users,
       (2 * greatest(50, round(2500 * sqrt(:scale))))::int AS n_products
\gset
-- A multiplier coprime with n_products, near n * 0.618 (golden ratio), so that consecutive
-- popularity ranks land far apart in product_id space.
SELECT min(m) AS pid_mult
FROM generate_series((:n_products * 0.618)::int, :n_products) m
WHERE gcd(m, :n_products) = 1
\gset

\echo '==> Generating SQL Dojo dataset: scale=':scale' users=':n_users' products=':n_products

-- -----------------------------------------------------------------------------
-- 0. Reset. Everything lives in "public" (the dataset) and "_dojo" (internals).
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS events, reviews, order_items, orders, subscriptions,
                     product_prices, products, categories, users CASCADE;
DROP SCHEMA IF EXISTS _dojo CASCADE;
-- lab schemas (Levels 6+) are rebuilt on demand from the new data
DROP SCHEMA IF EXISTS lab, partner, dq, mart, supplier, crm, stream, archive CASCADE;
CREATE SCHEMA _dojo;

-- Uniform [0,1) "random" number derived from a key and a salt.
CREATE FUNCTION _dojo.rnd(k bigint, salt int) RETURNS float8
  LANGUAGE sql IMMUTABLE PARALLEL SAFE
  AS $$ SELECT ((hashint8extended(k, salt) >> 11) & 9007199254740991)::float8 / 9007199254740992.0 $$;

-- Standard normal via Box-Muller.
CREATE FUNCTION _dojo.rnorm(k bigint, salt int) RETURNS float8
  LANGUAGE sql IMMUTABLE PARALLEL SAFE
  AS $$ SELECT sqrt(-2 * ln(1 - _dojo.rnd(k, salt))) * cos(2 * pi() * _dojo.rnd(k, salt + 7919)) $$;

-- Uniform pick from an array.
CREATE FUNCTION _dojo.pick(arr text[], k bigint, salt int) RETURNS text
  LANGUAGE sql IMMUTABLE PARALLEL SAFE
  AS $$ SELECT arr[1 + floor(_dojo.rnd(k, salt) * cardinality(arr))::int] $$;

-- Popularity rank -> product_id. x -> (x * m + offset) mod n is a bijection on [0, n) when
-- gcd(m, n) = 1, so popular products are scattered across the id space.
CREATE FUNCTION _dojo.pid(rnk bigint, n int, m int) RETURNS int
  LANGUAGE sql IMMUTABLE PARALLEL SAFE
  AS $$ SELECT ((rnk * m + n / 3) % n)::int + 1 $$;

-- Popularity-skewed rank in [0, n): low ranks are far more likely (a long tail).
CREATE FUNCTION _dojo.skewed_rank(k bigint, salt int, n int) RETURNS bigint
  LANGUAGE sql IMMUTABLE PARALLEL SAFE
  AS $$ SELECT floor(power(_dojo.rnd(k, salt), 1.6) * n)::bigint $$;

-- The j-th product in a session's cart. Product ranks come in pairs (2k, 2k+1)
-- from the same category; the second cart item is often the "companion".
CREATE FUNCTION _dojo.cart_pid(sid bigint, j int, rank1 bigint, n int, m int) RETURNS int
  LANGUAGE sql IMMUTABLE PARALLEL SAFE
  AS $$ SELECT _dojo.pid(CASE WHEN j = 1 THEN rank1
                             WHEN j = 2 AND _dojo.rnd(sid, 35) < 0.45 THEN rank1 # 1
                             ELSE _dojo.skewed_rank(sid * 8 + j, 36, n) END, n, m) $$;

CREATE FUNCTION _dojo.qty(sid bigint, j int) RETURNS int
  LANGUAGE sql IMMUTABLE PARALLEL SAFE
  AS $$ SELECT 1 + CASE WHEN _dojo.rnd(sid * 8 + j, 37) < 0.12
                        THEN 1 + floor(_dojo.rnd(sid * 8 + j, 38) * 3)::int ELSE 0 END $$;

-- Seconds between session start and its i-th event. Strictly increasing in i.
CREATE FUNCTION _dojo.evt_offset(sid bigint, i int, pace float8) RETURNS interval
  LANGUAGE sql IMMUTABLE PARALLEL SAFE
  AS $$ SELECT make_interval(secs => round(((i - 1) * pace + _dojo.rnd(sid * 64 + i, 40) * 0.9 * pace)::numeric, 3)::float8) $$;

CREATE FUNCTION _dojo.first_name(k bigint) RETURNS text
  LANGUAGE sql IMMUTABLE PARALLEL SAFE
  AS $$ SELECT _dojo.pick(ARRAY['Maria','James','Aisha','Wei','Liam','Sofia','Noah','Priya','Lucas','Emma',
    'Mateo','Olivia','Hiro','Fatima','Ethan','Chloe','Arjun','Mia','Leon','Ava','Diego','Yuki','Omar','Zoe',
    'Daniel','Isabella','Kofi','Hannah','Ravi','Lea','Gabriel','Nora','Samuel','Elena','Tariq','Grace',
    'Felix','Amara','Jonas','Ines','Carlos','Mei','Adam','Laila','Henry','Ana','Oscar','Sara','Theo','Julia',
    'Kenji','Lucia','Ben','Nia','Max','Rosa','Ali','Clara','Sam','Ivy'], k, 101) $$;

CREATE FUNCTION _dojo.last_name(k bigint) RETURNS text
  LANGUAGE sql IMMUTABLE PARALLEL SAFE
  AS $$ SELECT _dojo.pick(ARRAY['Garcia','Smith','Khan','Chen','Murphy','Rossi','Johnson','Patel','Silva','Martin',
    'Lopez','Brown','Tanaka','Ahmed','Wilson','Dubois','Sharma','Muller','Schmidt','Taylor','Hernandez','Sato',
    'Hassan','Clarke','Kim','Romano','Mensah','Fischer','Gupta','Weber','Santos','Novak','Cohen','Ivanova',
    'Ali','Walker','Becker','Okafor','Lindqvist','Costa','Moreno','Wang','Nguyen','Jensen','Lee','Ferreira',
    'Bauer','Haddad','Young','Park','Suzuki','Rivera','Evans','Diaz','Kowalski','Hoffmann','Reyes','Morgan',
    'Singh','Baker'], k, 102) $$;

CREATE FUNCTION _dojo.base_email(k bigint) RETURNS text
  LANGUAGE sql IMMUTABLE PARALLEL SAFE
  AS $$ SELECT lower(_dojo.first_name(k)) || '.' || lower(_dojo.last_name(k)) || k::text || '@' ||
               _dojo.pick(ARRAY['gmail.com','gmail.com','gmail.com','outlook.com','yahoo.com','icloud.com',
                               'proton.me','hey.com'], k, 103) $$;

-- -----------------------------------------------------------------------------
-- 1. Categories: a fixed 3-level tree (top -> mid -> leaf).
-- -----------------------------------------------------------------------------
\echo '--> categories'
CREATE TABLE categories (
  category_id int PRIMARY KEY,
  parent_id   int REFERENCES categories (category_id),
  name        text NOT NULL
);

CREATE TABLE _dojo.leaf_price (category_id int PRIMARY KEY, typical_price numeric NOT NULL);

WITH c(category_id, parent_id, name, typical_price) AS (VALUES
  (1, NULL, 'Electronics', NULL), (2, NULL, 'Home & Kitchen', NULL), (3, NULL, 'Fashion', NULL),
  (4, NULL, 'Sports & Outdoors', NULL), (5, NULL, 'Books', NULL), (6, NULL, 'Toys & Games', NULL),
  (10, 1, 'Audio', NULL), (11, 1, 'Computers', NULL), (12, 1, 'Phones', NULL), (13, 1, 'Cameras', NULL),
  (20, 2, 'Kitchen', NULL), (21, 2, 'Furniture', NULL), (22, 2, 'Decor', NULL),
  (30, 3, 'Men', NULL), (31, 3, 'Women', NULL), (32, 3, 'Accessories', NULL),
  (40, 4, 'Fitness', NULL), (41, 4, 'Camping', NULL), (42, 4, 'Cycling', NULL),
  (50, 5, 'Fiction', NULL), (51, 5, 'Non-Fiction', NULL), (52, 5, 'Technical', NULL),
  (60, 6, 'Board Games', NULL), (61, 6, 'Puzzles', NULL), (62, 6, 'Video Games', NULL),
  (100, 10, 'Headphones', 120), (101, 10, 'Speakers', 90), (102, 10, 'Earbuds', 80),
  (110, 11, 'Laptops', 1100), (111, 11, 'Monitors', 300), (112, 11, 'Keyboards', 70), (113, 11, 'Mice', 40),
  (120, 12, 'Smartphones', 700), (121, 12, 'Phone Cases', 20), (122, 12, 'Chargers', 25),
  (130, 13, 'Mirrorless Cameras', 1200), (131, 13, 'Lenses', 500), (132, 13, 'Tripods', 60),
  (200, 20, 'Cookware', 80), (201, 20, 'Knives', 60), (202, 20, 'Small Appliances', 120), (203, 20, 'Coffee', 30),
  (210, 21, 'Office Chairs', 250), (211, 21, 'Desks', 350), (212, 21, 'Shelving', 120),
  (220, 22, 'Lighting', 60), (221, 22, 'Rugs', 150), (222, 22, 'Wall Art', 45),
  (300, 30, 'Shirts', 35), (301, 30, 'Shoes', 90), (302, 30, 'Jackets', 130),
  (310, 31, 'Dresses', 70), (311, 31, 'Shoes', 95), (312, 31, 'Handbags', 120),
  (320, 32, 'Watches', 200), (321, 32, 'Sunglasses', 80), (322, 32, 'Jewelry', 90),
  (400, 40, 'Yoga', 35), (401, 40, 'Weights', 70), (402, 40, 'Cardio Machines', 600),
  (410, 41, 'Tents', 220), (411, 41, 'Sleeping Bags', 110), (412, 41, 'Camp Stoves', 70),
  (420, 42, 'Bikes', 800), (421, 42, 'Helmets', 70), (422, 42, 'Bike Lights', 35),
  (500, 50, 'Sci-Fi', 16), (501, 50, 'Mystery', 15), (502, 50, 'Fantasy', 17),
  (510, 51, 'Biography', 20), (511, 51, 'Science', 22), (512, 51, 'History', 21),
  (520, 52, 'Programming', 45), (521, 52, 'Databases', 50), (522, 52, 'Data Science', 48),
  (600, 60, 'Strategy Games', 50), (601, 60, 'Party Games', 25), (602, 60, 'Family Games', 30),
  (610, 61, 'Jigsaw Puzzles', 22), (611, 61, '3D Puzzles', 35),
  (620, 62, 'Console Games', 60), (621, 62, 'PC Games', 40)
), ins AS (
  INSERT INTO categories SELECT category_id, parent_id, name FROM c
)
INSERT INTO _dojo.leaf_price SELECT category_id, typical_price FROM c WHERE typical_price IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 2. Users. Signups accelerate over 2023-2025; ids follow signup order.
-- -----------------------------------------------------------------------------
\echo '--> users'
BEGIN;
CREATE TABLE users (
  user_id         bigint PRIMARY KEY,
  email           text NOT NULL,
  full_name       text NOT NULL,
  country         char(2) NOT NULL,
  timezone        text NOT NULL,
  signup_at       timestamptz NOT NULL,
  referral_source text,
  referred_by     bigint,
  birth_date      date,
  is_test         boolean NOT NULL DEFAULT false
);

INSERT INTO users
WITH base AS (
  SELECT g, CASE WHEN _dojo.rnd(g, 1) < 0.3 THEN _dojo.rnd(g, 2) ELSE sqrt(_dojo.rnd(g, 2)) END AS t
  FROM generate_series(1, :n_users) g
), ordered AS (
  SELECT row_number() OVER (ORDER BY t, g) AS user_id, t FROM base
), a AS (
  SELECT user_id,
         date_trunc('second', timestamptz '2023-01-01 00:00:00+00' + t * interval '1095 days 23 hours') AS signup_at,
         _dojo.rnd(user_id, 3) AS r_country,
         _dojo.rnd(user_id, 4) AS r_tz,
         _dojo.rnd(user_id, 11) < 0.001 AS is_test,
         user_id > 100 AND _dojo.rnd(user_id, 9) < 0.01 AS is_dup,
         (user_id - 1 - floor(_dojo.rnd(user_id, 10) * least(user_id - 1, 5000)))::bigint AS dup_of,
         _dojo.rnd(user_id, 13) AS r_ref
  FROM ordered
), b AS (
  SELECT a.*,
         CASE WHEN r_country < 0.40 THEN 'US' WHEN r_country < 0.50 THEN 'GB' WHEN r_country < 0.58 THEN 'DE'
              WHEN r_country < 0.64 THEN 'FR' WHEN r_country < 0.70 THEN 'CA' WHEN r_country < 0.78 THEN 'IN'
              WHEN r_country < 0.84 THEN 'BR' WHEN r_country < 0.88 THEN 'AU' WHEN r_country < 0.92 THEN 'JP'
              WHEN r_country < 0.96 THEN 'MX' WHEN r_country < 0.98 THEN 'NL' ELSE 'ES' END AS country,
         CASE WHEN is_test THEN NULL
              WHEN r_ref < 0.20 THEN NULL WHEN r_ref < 0.50 THEN 'organic' WHEN r_ref < 0.70 THEN 'ads'
              WHEN r_ref < 0.85 THEN 'social' WHEN r_ref < 0.95 THEN 'referral' ELSE 'email' END AS referral_source
  FROM a
)
SELECT user_id,
       CASE WHEN is_test THEN 'qa.bot' || user_id || '@larkspur.test'
            WHEN is_dup THEN
              CASE WHEN _dojo.rnd(user_id, 12) < 0.4 THEN upper(_dojo.base_email(dup_of))
                   WHEN _dojo.rnd(user_id, 12) < 0.7 THEN initcap(_dojo.base_email(dup_of))
                   ELSE _dojo.base_email(dup_of) || ' ' END
            ELSE _dojo.base_email(user_id) END,
       CASE WHEN is_test THEN 'QA Bot ' || user_id
            ELSE _dojo.first_name(CASE WHEN is_dup THEN dup_of ELSE user_id END) || ' ' ||
                 _dojo.last_name(CASE WHEN is_dup THEN dup_of ELSE user_id END) END,
       country,
       CASE country
         WHEN 'US' THEN CASE WHEN r_tz < 0.47 THEN 'America/New_York' WHEN r_tz < 0.76 THEN 'America/Chicago'
                             WHEN r_tz < 0.83 THEN 'America/Denver' ELSE 'America/Los_Angeles' END
         WHEN 'CA' THEN CASE WHEN r_tz < 0.6 THEN 'America/Toronto' ELSE 'America/Vancouver' END
         WHEN 'GB' THEN 'Europe/London'   WHEN 'DE' THEN 'Europe/Berlin'   WHEN 'FR' THEN 'Europe/Paris'
         WHEN 'NL' THEN 'Europe/Amsterdam' WHEN 'ES' THEN 'Europe/Madrid'  WHEN 'IN' THEN 'Asia/Kolkata'
         WHEN 'JP' THEN 'Asia/Tokyo'      WHEN 'AU' THEN 'Australia/Sydney' WHEN 'BR' THEN 'America/Sao_Paulo'
         ELSE 'America/Mexico_City' END,
       signup_at,
       referral_source,
       CASE WHEN referral_source = 'referral' AND user_id > 1
            THEN 1 + floor(power(_dojo.rnd(user_id, 14), 3) * (user_id - 1))::bigint END,
       CASE WHEN _dojo.rnd(user_id, 15) < 0.05 THEN NULL
            ELSE signup_at::date - (365.25 * (18 + power(_dojo.rnd(user_id, 16), 1.6) * 55))::int END,
       is_test
FROM b;
COMMIT;

-- -----------------------------------------------------------------------------
-- 3. Products and their price history.
-- -----------------------------------------------------------------------------
\echo '--> products, product_prices'
BEGIN;
CREATE TABLE products (
  product_id  int PRIMARY KEY,
  category_id int NOT NULL,
  name        text NOT NULL,
  brand       text NOT NULL,
  price       numeric(10,2) NOT NULL,   -- CURRENT list price (see product_prices for history)
  created_at  timestamptz NOT NULL
);
CREATE TABLE product_prices (
  product_id int NOT NULL,
  valid_from timestamptz NOT NULL,
  valid_to   timestamptz,               -- NULL = still current
  price      numeric(10,2) NOT NULL,
  PRIMARY KEY (product_id, valid_from)
);

CREATE TEMP TABLE leaves AS
SELECT array_agg(category_id ORDER BY category_id) AS ids FROM _dojo.leaf_price;

CREATE TEMP TABLE p AS
SELECT _dojo.pid(rnk, :n_products, :pid_mult) AS product_id,
       (SELECT ids[1 + floor(_dojo.rnd(rnk / 2, 60) * cardinality(ids))::int] FROM leaves) AS category_id,
       rnk
FROM generate_series(0, :n_products - 1) rnk;

CREATE TEMP TABLE pp AS
SELECT p.product_id, p.category_id,
       _dojo.pick(ARRAY['Nimbus','Vertex','Aurora','Kestrel','Lumen','Orbit','Pioneer','Quanta','Solace','Tundra',
                       'Zephyr','Atlas','Beacon','Cobalt','Drift','Ember','Fable','Granite','Harbor','Ion',
                       'Juniper','Krypton','Lyra','Mosaic','Nova','Onyx','Prism','Ridge','Sable','Terra'],
                 p.product_id, 61) AS brand,
       lp.typical_price * exp(0.45 * _dojo.rnorm(p.product_id, 62)) AS base_price,
       timestamptz '2022-01-01' + _dojo.rnd(p.product_id, 63) * interval '360 days' AS created_at,
       floor(_dojo.rnd(p.product_id, 64) * 4)::int AS n_changes,
       c.name AS leaf_name
FROM p
JOIN _dojo.leaf_price lp USING (category_id)
JOIN categories c USING (category_id);

INSERT INTO product_prices (product_id, valid_from, price)
SELECT product_id,
       CASE WHEN k = 0 THEN date_trunc('second', created_at)
            ELSE date_trunc('day', timestamptz '2023-02-01'
                 + ((k - 0.5 + 0.8 * (_dojo.rnd(product_id * 8 + k, 65) - 0.5)) / n_changes) * interval '1030 days') END,
       greatest(2.99, round(base_price * CASE WHEN k = 0 THEN 1 ELSE 0.8 + 0.4 * _dojo.rnd(product_id * 8 + k, 66) END) - 0.01)
FROM pp, generate_series(0, n_changes) k;

UPDATE product_prices x
SET valid_to = n.next_from
FROM (SELECT product_id, valid_from,
             lead(valid_from) OVER (PARTITION BY product_id ORDER BY valid_from) AS next_from
      FROM product_prices) n
WHERE x.product_id = n.product_id AND x.valid_from = n.valid_from AND n.next_from IS NOT NULL;

INSERT INTO products
SELECT pp.product_id, pp.category_id,
       pp.brand || ' ' || pp.leaf_name || ' ' || upper(substr(md5(pp.product_id::text), 1, 2)) || '-' || (100 + pp.product_id % 900),
       pp.brand,
       cur.price,
       date_trunc('second', pp.created_at)
FROM pp
JOIN product_prices cur ON cur.product_id = pp.product_id AND cur.valid_to IS NULL;
COMMIT;

-- -----------------------------------------------------------------------------
-- 4. Sessions (internal only -- you have to rediscover them from events!).
-- -----------------------------------------------------------------------------
\echo '--> sessions (internal)'
CREATE UNLOGGED TABLE _dojo.stg_sessions AS
WITH u AS (
  SELECT user_id, signup_at, timezone, is_test,
         -- a few real people use the app almost daily
         NOT is_test AND _dojo.rnd(user_id, 29) < 0.005 AS habitual,
         CASE WHEN is_test OR _dojo.rnd(user_id, 29) < 0.005 THEN 1.0 ELSE power(_dojo.rnd(user_id, 20), 2) END AS a,
         CASE WHEN _dojo.rnd(user_id, 23) < 0.55 THEN 'mobile'
              WHEN _dojo.rnd(user_id, 23) < 0.90 THEN 'desktop' ELSE 'tablet' END AS primary_device
  FROM users
), u2 AS (
  SELECT u.*,
         least(timestamptz '2026-01-01',
               signup_at + (-ln(1 - _dojo.rnd(user_id, 21)) * (30 + 700 * a)) * interval '1 day') AS active_until
  FROM u
), u3 AS (
  SELECT u2.*,
         extract(epoch FROM active_until - signup_at) / 86400 AS active_days
  FROM u2
), s AS MATERIALIZED (
  SELECT u3.user_id, u3.is_test, u3.primary_device,
         u3.user_id * 100000 + s AS sid,
         CASE WHEN s = 1 THEN u3.signup_at
              ELSE ((date_trunc('day', u3.signup_at AT TIME ZONE u3.timezone)
                     + (1 + floor(_dojo.rnd(u3.user_id * 100000 + s, 22) * greatest(u3.active_days - 1, 0))) * interval '1 day'
                     + (6 + floor(power(_dojo.rnd(u3.user_id * 100000 + s, 26), 0.7) * 18)) * interval '1 hour'
                     + floor(_dojo.rnd(u3.user_id * 100000 + s, 27) * 3600) * interval '1 second')
                    AT TIME ZONE u3.timezone) END AS started_at
  FROM u3,
       generate_series(1, 1 + floor(u3.a * u3.active_days / CASE WHEN u3.is_test THEN 6 WHEN u3.habitual THEN 1.3 ELSE 10 END)::int) s
), s2 AS MATERIALIZED (
  -- MATERIALIZED stops Postgres from inlining started_at into every expression below
  SELECT s.*,
         CASE WHEN _dojo.rnd(sid, 24) < 0.8 THEN primary_device
              ELSE _dojo.pick(ARRAY['mobile','desktop','tablet'], sid, 25) END AS device,
         is_test OR _dojo.rnd(sid, 28) < 0.85 AS logged_in,
         CASE WHEN (extract(month FROM started_at) = 11 AND extract(day FROM started_at) >= 22)
                OR (extract(month FROM started_at) = 12 AND extract(day FROM started_at) <= 2) THEN 2.5
              WHEN extract(month FROM started_at) IN (11, 12) THEN 1.5
              WHEN extract(month FROM started_at) = 1 THEN 0.8
              ELSE 1.0 END AS season
  FROM s
  WHERE started_at < timestamptz '2026-01-01'
), s3 AS (
  SELECT s2.*,
         0.10 * season * CASE device WHEN 'mobile' THEN 0.75 WHEN 'desktop' THEN 1.4 ELSE 1.0 END AS p4,
         _dojo.rnd(sid, 30) AS u
  FROM s2
), s4 AS MATERIALIZED (
  SELECT sid, user_id, logged_in, device, started_at,
         CASE WHEN is_test THEN CASE WHEN u < 0.3 THEN 4 ELSE 1 END
              ELSE LEAST(CASE WHEN NOT logged_in THEN 2 ELSE 4 END,
                         CASE WHEN u < p4 THEN 4 WHEN u < p4 + 0.035 THEN 3 WHEN u < p4 + 0.155 THEN 2
                              WHEN u < p4 + 0.485 THEN 1 ELSE 0 END) END AS depth,
         1 + floor(power(_dojo.rnd(sid, 31), 2) * 14)::int AS n_browse0,
         1 + floor(power(_dojo.rnd(sid, 32), 2.5) * 4)::int AS k_cart,
         15 + power(_dojo.rnd(sid, 33), 1.5) * 200 AS pace,
         _dojo.skewed_rank(sid, 34, :n_products) AS rank1
  FROM s3
)
SELECT s4.*,
       CASE WHEN depth >= 1 THEN greatest(n_browse0, k_cart + 1) ELSE n_browse0 END AS n_browse,
       CASE WHEN depth >= 1 THEN greatest(n_browse0, k_cart + 1) ELSE n_browse0 END
         + CASE WHEN depth >= 2 THEN k_cart ELSE 0 END
         + CASE WHEN depth >= 3 THEN 1 ELSE 0 END
         + CASE WHEN depth >= 4 THEN 1 ELSE 0 END AS n_total
FROM s4;

-- -----------------------------------------------------------------------------
-- 5. Orders: one per purchasing session.
-- -----------------------------------------------------------------------------
\echo '--> orders'
CREATE UNLOGGED TABLE _dojo.stg_orders AS
SELECT row_number() OVER (ORDER BY purchased_at, sid) AS order_id, x.*
FROM (SELECT sid, user_id, device, k_cart, rank1,
             date_trunc('second', started_at + _dojo.evt_offset(sid, n_total, pace)) AS purchased_at
      FROM _dojo.stg_sessions
      WHERE depth = 4) x
WHERE purchased_at < timestamptz '2026-01-01';
CREATE INDEX ON _dojo.stg_orders (sid);

BEGIN;
CREATE TABLE orders (
  order_id     bigint PRIMARY KEY,
  user_id      bigint NOT NULL,
  created_at   timestamptz NOT NULL,
  status       text NOT NULL,          -- pending | shipped | delivered | returned | cancelled
  device       text NOT NULL,
  ship_country char(2) NOT NULL,
  carrier      text,                   -- NULL until the order ships
  shipped_at   timestamptz,
  delivered_at timestamptz
);

INSERT INTO orders
WITH o AS (
  SELECT so.order_id, so.user_id, so.purchased_at, so.device, u.country,
         CASE WHEN _dojo.rnd(so.order_id, 70) < 0.04 THEN true ELSE false END AS cancelled,
         CASE WHEN u.country = 'US' THEN
                CASE WHEN _dojo.rnd(so.order_id, 71) < 0.4 THEN 'UPS' WHEN _dojo.rnd(so.order_id, 71) < 0.7 THEN 'FedEx' ELSE 'USPS' END
              ELSE
                CASE WHEN _dojo.rnd(so.order_id, 71) < 0.7 THEN 'DHL' WHEN _dojo.rnd(so.order_id, 71) < 0.85 THEN 'UPS' ELSE 'FedEx' END
         END AS carrier0,
         _dojo.rnd(so.order_id, 73) AS rt
  FROM _dojo.stg_orders so
  JOIN users u ON u.user_id = so.user_id
), o2 AS (
  SELECT o.*,
         date_trunc('second', purchased_at + (4 + power(_dojo.rnd(order_id, 72), 2) * 96) * interval '1 hour') AS ship_ts
  FROM o
), o3 AS (
  SELECT o2.*,
         date_trunc('second', ship_ts + 24 * interval '1 hour' * CASE carrier0
           WHEN 'FedEx' THEN 1 + rt * 3
           WHEN 'UPS'   THEN 2 + rt * 3
           WHEN 'USPS'  THEN 2 + power(rt, 2.5) * 9
           ELSE 3 + power(rt, 1.5) * 10 END) AS deliver_ts
  FROM o2
)
SELECT order_id, user_id, purchased_at,
       CASE WHEN cancelled THEN 'cancelled'
            WHEN ship_ts >= '2026-01-01' THEN 'pending'
            WHEN deliver_ts >= '2026-01-01' THEN 'shipped'
            WHEN _dojo.rnd(order_id, 74) < 0.05 THEN 'returned'
            ELSE 'delivered' END,
       device, country,
       CASE WHEN cancelled OR ship_ts >= '2026-01-01' THEN NULL ELSE carrier0 END,
       CASE WHEN cancelled OR ship_ts >= '2026-01-01' THEN NULL ELSE ship_ts END,
       CASE WHEN cancelled OR deliver_ts >= '2026-01-01' THEN NULL
            -- a broken scanner occasionally records delivery before shipment
            WHEN _dojo.rnd(order_id, 75) < 0.002 THEN ship_ts - (1 + floor(_dojo.rnd(order_id, 76) * 30)) * interval '1 hour'
            ELSE deliver_ts END
FROM o3;
COMMIT;

\echo '--> order_items'
BEGIN;
CREATE TABLE order_items (
  order_id   bigint NOT NULL,
  line_no    int NOT NULL,
  product_id int NOT NULL,
  quantity   int NOT NULL,
  unit_price numeric(10,2) NOT NULL,   -- price actually charged (price in effect at order time)
  PRIMARY KEY (order_id, line_no)
);

INSERT INTO order_items
SELECT so.order_id, j, x.product_id, _dojo.qty(so.sid, j), pr.price
FROM _dojo.stg_orders so
CROSS JOIN LATERAL generate_series(1, so.k_cart) j
CROSS JOIN LATERAL (SELECT _dojo.cart_pid(so.sid, j, so.rank1, :n_products, :pid_mult) AS product_id) x
CROSS JOIN LATERAL (SELECT price FROM product_prices pp
                    WHERE pp.product_id = x.product_id AND pp.valid_from <= so.purchased_at
                    ORDER BY pp.valid_from DESC LIMIT 1) pr;
COMMIT;

-- -----------------------------------------------------------------------------
-- 6. Events: the big one. Clickstream reconstructed from the hidden sessions.
-- -----------------------------------------------------------------------------
\echo '--> events (the big one, a quarter at a time)'
-- Built one quarter at a time: each chunk sorts only its own rows, so the temporary disk space
-- needed stays small even at large scales. Event ids continue across chunks, so the result is
-- identical to one big INSERT ... ORDER BY occurred_at.
CREATE INDEX ON _dojo.stg_sessions (started_at);
CREATE UNLOGGED TABLE _dojo.gen_state AS SELECT 0::bigint AS next_id;

BEGIN;
CREATE TABLE events (
  event_id    bigint NOT NULL,
  occurred_at timestamptz NOT NULL,
  user_id     bigint,                  -- NULL when the visitor was not logged in
  device      text NOT NULL,
  event_type  text NOT NULL,           -- page_view | search | product_view | add_to_cart | checkout_started | purchase
  product_id  int,
  properties  jsonb
);

CREATE FUNCTION _dojo.gen_events(lo timestamptz, hi timestamptz, np int, pm int) RETURNS text
LANGUAGE plpgsql AS $gen$
DECLARE
  off bigint;
  n   bigint;
BEGIN
  SELECT next_id INTO off FROM _dojo.gen_state;
  INSERT INTO events
  SELECT off + row_number() OVER (ORDER BY occurred_at, sid, i, dup) AS event_id,
         occurred_at, user_id, device, event_type, product_id, properties
  FROM (
    SELECT e.*,
           CASE
             WHEN event_type = 'page_view' AND i = 1 THEN jsonb_build_object('path', '/', 'referrer',
               CASE WHEN r < 0.35 THEN 'google' WHEN r < 0.60 THEN 'direct' WHEN r < 0.70 THEN 'instagram'
                    WHEN r < 0.78 THEN 'tiktok' WHEN r < 0.85 THEN 'newsletter' WHEN r < 0.90 THEN 'bing'
                    WHEN r < 0.95 THEN 'partner_blog' ELSE 'facebook' END)
             WHEN event_type = 'page_view' THEN jsonb_build_object('path',
               _dojo.pick(ARRAY['/deals','/new','/account','/help','/wishlist','/category'], sid * 64 + i, 45))
             WHEN event_type = 'search' THEN jsonb_build_object('query',
               CASE WHEN r < 0.15 THEN 'cheap ' WHEN r < 0.25 THEN 'best ' ELSE '' END ||
               _dojo.pick(ARRAY['headphones','laptop','monitor','keyboard','phone case','charger','camera','lens',
                               'coffee','knife set','office chair','desk','lamp','rug','shirt','running shoes',
                               'jacket','dress','handbag','watch','sunglasses','yoga mat','dumbbells','tent',
                               'sleeping bag','bike','helmet','sci-fi books','mystery novel','sql book',
                               'board games','puzzle','video games','Headphones','LAPTOP','earbuds '], sid * 64 + i, 46))
             WHEN event_type = 'product_view' THEN jsonb_build_object('source',
               CASE WHEN r < 0.45 THEN 'search' WHEN r < 0.75 THEN 'category' WHEN r < 0.95 THEN 'recommendation' ELSE 'email' END)
             WHEN event_type = 'add_to_cart' THEN jsonb_build_object('quantity', _dojo.qty(sid, i - n_browse))
             WHEN event_type = 'checkout_started' THEN jsonb_build_object('items', k_cart)
             WHEN event_type = 'purchase' THEN jsonb_build_object('order_id', order_id)
           END AS properties
    FROM (
      SELECT s.sid, i, dup, s.n_browse, s.k_cart, o.order_id,
             s.started_at + _dojo.evt_offset(s.sid, i, s.pace) AS occurred_at,
             CASE WHEN s.logged_in THEN s.user_id END AS user_id,
             s.device,
             _dojo.rnd(s.sid * 64 + i, 44) AS r,
             CASE
               WHEN i = 1 THEN 'page_view'
               WHEN i <= s.n_browse AND s.depth >= 1 AND i <= s.k_cart + 1 THEN 'product_view'
               WHEN i <= s.n_browse THEN
                 CASE WHEN s.depth = 0 THEN CASE WHEN _dojo.rnd(s.sid * 64 + i, 42) < 0.7 THEN 'page_view' ELSE 'search' END
                      WHEN _dojo.rnd(s.sid * 64 + i, 42) < 0.5 THEN 'product_view'
                      WHEN _dojo.rnd(s.sid * 64 + i, 42) < 0.8 THEN 'page_view' ELSE 'search' END
               WHEN s.depth >= 2 AND i <= s.n_browse + s.k_cart THEN 'add_to_cart'
               WHEN s.depth >= 3 AND i = s.n_browse + s.k_cart + 1 THEN 'checkout_started'
               ELSE 'purchase'
             END AS event_type,
             CASE
               WHEN i = 1 THEN NULL
               WHEN i <= s.n_browse AND s.depth >= 1 AND i <= s.k_cart + 1 THEN _dojo.cart_pid(s.sid, i - 1, s.rank1, np, pm)
               WHEN i <= s.n_browse THEN
                 CASE WHEN s.depth >= 1 AND _dojo.rnd(s.sid * 64 + i, 42) < 0.5
                      THEN _dojo.pid(_dojo.skewed_rank(s.sid * 64 + i, 43, np), np, pm) END
               WHEN s.depth >= 2 AND i <= s.n_browse + s.k_cart THEN _dojo.cart_pid(s.sid, i - s.n_browse, s.rank1, np, pm)
             END AS product_id
      FROM _dojo.stg_sessions s
      CROSS JOIN LATERAL generate_series(1, s.n_total) i
      -- at-least-once delivery: a small share of events arrive twice
      CROSS JOIN LATERAL generate_series(1, CASE WHEN _dojo.rnd(s.sid * 64 + i, 41) < 0.004 THEN 2 ELSE 1 END) dup
      LEFT JOIN _dojo.stg_orders o ON o.sid = s.sid AND i = s.n_total AND s.depth = 4
      -- only sessions that can have events in [lo, hi); a session lasts well under 6 hours
      WHERE s.started_at >= lo - interval '6 hours' AND s.started_at < hi
      OFFSET 0  -- optimisation fence: compute event_type once instead of once per reference
    ) e
    WHERE occurred_at >= lo AND occurred_at < hi
      -- purchases only exist if the order exists, and ad blockers eat ~3% of them
      AND NOT (event_type = 'purchase' AND (order_id IS NULL OR _dojo.rnd(sid, 50) < 0.03))
  ) ev
  ORDER BY occurred_at, sid, i, dup;
  GET DIAGNOSTICS n = ROW_COUNT;
  UPDATE _dojo.gen_state SET next_id = off + n;
  RETURN format('    %s  %s events', to_char(lo, 'YYYY "Q"Q'), to_char(n, 'FM999,999,999'));
END
$gen$;

\pset tuples_only on
\pset format unaligned
SELECT format('SELECT _dojo.gen_events(%L, %L, %s, %s)', m, m + interval '3 months', :n_products, :pid_mult)
FROM generate_series(timestamptz '2023-01-01', timestamptz '2025-10-01', interval '3 months') AS m
\gexec
\pset tuples_only off
\pset format aligned

ALTER TABLE events ADD PRIMARY KEY (event_id);
COMMIT;

-- -----------------------------------------------------------------------------
-- 7. Reviews: some customers review what they received.
-- -----------------------------------------------------------------------------
\echo '--> reviews'
BEGIN;
CREATE TABLE reviews (
  review_id  bigint PRIMARY KEY,
  product_id int NOT NULL,
  user_id    bigint NOT NULL,
  order_id   bigint NOT NULL,
  rating     smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  created_at timestamptz NOT NULL
);

INSERT INTO reviews
SELECT row_number() OVER (ORDER BY created_at, order_id, line_no), product_id, user_id, order_id, rating, created_at
FROM (
  SELECT oi.order_id, oi.line_no, oi.product_id, o.user_id,
         greatest(1, least(5, round(
           2.6 + 2.2 * _dojo.rnd(oi.product_id, 80)                    -- product quality
           + 0.9 * _dojo.rnorm(oi.order_id * 8 + oi.line_no, 81)        -- personal taste
           - CASE WHEN o.status = 'returned' THEN 1.5 ELSE 0 END
           - CASE WHEN o.delivered_at - o.shipped_at > interval '7 days' THEN 0.7 ELSE 0 END)))::smallint AS rating,
         date_trunc('second', o.delivered_at
           + (1 + power(_dojo.rnd(oi.order_id * 8 + oi.line_no, 82), 2) * 30) * interval '1 day') AS created_at
  FROM order_items oi
  JOIN orders o ON o.order_id = oi.order_id
  WHERE o.status IN ('delivered', 'returned')
    AND o.delivered_at > o.shipped_at
    AND _dojo.rnd(oi.order_id * 8 + oi.line_no, 83) < CASE WHEN o.status = 'returned' THEN 0.35 ELSE 0.10 END
) r
WHERE created_at < timestamptz '2026-01-01';
COMMIT;

-- -----------------------------------------------------------------------------
-- 8. Subscriptions: "Larkspur Plus" membership. People churn and come back.
-- -----------------------------------------------------------------------------
\echo '--> subscriptions'
BEGIN;
CREATE TABLE subscriptions (
  subscription_id bigint PRIMARY KEY,
  user_id         bigint NOT NULL,
  plan            text NOT NULL,           -- monthly | annual
  monthly_price   numeric(10,2) NOT NULL,  -- normalised: annual plans are price/12
  started_at      timestamptz NOT NULL,
  ended_at        timestamptz              -- NULL = still active
);

INSERT INTO subscriptions
WITH subscribers AS (
  SELECT user_id, signup_at,
         1 + (_dojo.rnd(user_id, 91) < 0.3)::int + (_dojo.rnd(user_id, 92) < 0.1)::int AS n_stints
  FROM users
  WHERE NOT is_test AND _dojo.rnd(user_id, 90) < 0.18
), stints AS (
  SELECT user_id, signup_at, k,
         _dojo.rnd(user_id * 4 + k, 93) < 0.3 AS annual,
         -- duration in months and the gap before this stint
         CASE WHEN _dojo.rnd(user_id * 4 + k, 93) < 0.3 THEN 12 * (1 + floor(power(_dojo.rnd(user_id * 4 + k, 94), 2) * 3))
              ELSE 1 + floor(power(_dojo.rnd(user_id * 4 + k, 94), 1.5) * 24) END::int AS months,
         CASE WHEN k = 1 THEN floor(-ln(1 - _dojo.rnd(user_id * 4 + k, 95)) * 60)
              ELSE 15 + floor(_dojo.rnd(user_id * 4 + k, 95) * 200) END::int AS gap_days
  FROM subscribers, generate_series(1, n_stints) k
), timeline AS (
  -- each stint starts gap_days after the previous one ended: a running sum
  SELECT s.*,
         signup_at
           + sum(gap_days) OVER w * interval '1 day'
           + (coalesce(sum(months) OVER w, 0) - months) * interval '1 month' AS started_at
  FROM stints s
  WINDOW w AS (PARTITION BY user_id ORDER BY k ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
), clean AS (
  SELECT user_id, k,
         CASE WHEN annual THEN 'annual' ELSE 'monthly' END AS plan,
         CASE WHEN annual THEN round(99.00 / 12, 2) ELSE 9.99 END AS monthly_price,
         date_trunc('second', started_at) AS started_at,
         date_trunc('second', started_at + months * interval '1 month') AS ended_at
  FROM timeline
  WHERE started_at < timestamptz '2026-01-01'
), with_bug AS (
  SELECT * FROM clean
  UNION ALL
  -- a billing-system bug created a second, overlapping subscription for a few users
  SELECT user_id, 9, plan, monthly_price,
         started_at + (3 + floor(_dojo.rnd(user_id, 96) * 20)) * interval '1 day',
         ended_at + (3 + floor(_dojo.rnd(user_id, 96) * 20)) * interval '1 day'
  FROM clean
  WHERE k = 1 AND _dojo.rnd(user_id, 97) < 0.01
)
SELECT row_number() OVER (ORDER BY started_at, user_id, k), user_id, plan, monthly_price, started_at,
       CASE WHEN ended_at >= timestamptz '2026-01-01' THEN NULL ELSE ended_at END
FROM with_bug
WHERE started_at < timestamptz '2026-01-01';
COMMIT;

-- -----------------------------------------------------------------------------
-- 9. Constraints, baseline indexes, statistics.
--    Deliberately minimal: primary keys, foreign keys and orders(user_id).
--    Adding the right indexes is part of the curriculum.
-- -----------------------------------------------------------------------------
\echo '--> constraints, indexes, VACUUM ANALYZE'
ALTER TABLE users          ADD FOREIGN KEY (referred_by) REFERENCES users (user_id);
ALTER TABLE products       ADD FOREIGN KEY (category_id) REFERENCES categories (category_id);
ALTER TABLE product_prices ADD FOREIGN KEY (product_id)  REFERENCES products (product_id);
ALTER TABLE orders         ADD FOREIGN KEY (user_id)     REFERENCES users (user_id);
ALTER TABLE order_items    ADD FOREIGN KEY (order_id)    REFERENCES orders (order_id);
ALTER TABLE order_items    ADD FOREIGN KEY (product_id)  REFERENCES products (product_id);
ALTER TABLE reviews        ADD FOREIGN KEY (order_id)    REFERENCES orders (order_id);
ALTER TABLE reviews        ADD FOREIGN KEY (product_id)  REFERENCES products (product_id);
ALTER TABLE reviews        ADD FOREIGN KEY (user_id)     REFERENCES users (user_id);
ALTER TABLE subscriptions  ADD FOREIGN KEY (user_id)     REFERENCES users (user_id);
CREATE INDEX orders_user_id_idx ON orders (user_id);

DROP TABLE _dojo.stg_sessions, _dojo.stg_orders, _dojo.leaf_price, _dojo.gen_state;
DROP FUNCTION _dojo.gen_events, _dojo.cart_pid, _dojo.qty, _dojo.evt_offset, _dojo.base_email, _dojo.first_name, _dojo.last_name,
              _dojo.skewed_rank, _dojo.pid, _dojo.pick, _dojo.rnorm, _dojo.rnd;

VACUUM (ANALYZE) users, categories, products, product_prices, orders, order_items, events, reviews, subscriptions;

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Bookkeeping for the dojo CLI.
CREATE TABLE _dojo.baseline_objects AS
SELECT 'index' AS kind, indexname AS name FROM pg_indexes WHERE schemaname = 'public';

CREATE TABLE _dojo.meta (key text PRIMARY KEY, value text NOT NULL);
INSERT INTO _dojo.meta VALUES
  ('scale', :'scale'),
  ('dataset_version', '1'),
  ('generated_at', now()::text);

\echo '==> Done.'
SELECT c.relname AS "table", to_char(c.reltuples, 'FM999,999,999,990') AS "rows",
       pg_size_pretty(pg_total_relation_size(c.oid)) AS "size"
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
ORDER BY pg_total_relation_size(c.oid) DESC;
