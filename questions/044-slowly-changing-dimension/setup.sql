-- Lab for Q044: weekly CRM snapshots and an empty type-2 history table.
DROP SCHEMA IF EXISTS crm CASCADE;
CREATE SCHEMA crm;

-- The CRM export: snapshot k (1, 2, 3) of a subset of customers.
CREATE FUNCTION crm.snapshot(k int)
RETURNS TABLE (user_id bigint, email text, country text, plan text, snapshot_at timestamptz)
LANGUAGE sql STABLE AS $$
  WITH base AS (
    SELECT u.user_id, lower(trim(u.email)) AS email, u.country::text AS country,
           abs(hashint8extended(u.user_id, 441)) % 100 AS h_first,
           abs(hashint8extended(u.user_id, 442)) % 100 AS h_country2,
           abs(hashint8extended(u.user_id, 443)) % 100 AS h_country3,
           abs(hashint8extended(u.user_id, 444)) % 100 AS h_plan,
           abs(hashint8extended(u.user_id, 445)) % 100 AS h_plan2,
           abs(hashint8extended(u.user_id, 446)) % 100 AS h_plan3,
           abs(hashint8extended(u.user_id, 447)) % 100 AS h_email3,
           (ARRAY['US','GB','DE','FR','CA','IN','BR','AU','JP','MX','NL','ES'])[1 + abs(hashint8extended(u.user_id, 448)) % 12] AS new_country
    FROM users u
    WHERE u.user_id % 25 = 0 AND NOT u.is_test
  )
  SELECT user_id,
         CASE WHEN k >= 3 AND h_email3 < 2 THEN 'new.' || email ELSE email END,
         CASE WHEN k >= 3 AND h_country3 < 2 THEN new_country
              WHEN k >= 2 AND h_country2 < 3 THEN new_country
              ELSE country END,
         -- plan flips: free <-> plus
         CASE WHEN ((h_plan < 20)::int + (k >= 2 AND h_plan2 < 8)::int + (k >= 3 AND h_plan3 < 8)::int) % 2 = 1
              THEN 'plus' ELSE 'free' END,
         timestamptz '2026-01-05 00:00+00' + (k - 1) * interval '7 days'
  FROM base
  -- most customers exist from the first snapshot, some sign up later
  WHERE CASE WHEN h_first < 5 THEN 3 WHEN h_first < 10 THEN 2 ELSE 1 END <= k
$$;

CREATE TABLE crm.customers (
  user_id     bigint PRIMARY KEY,
  email       text,
  country     text,
  plan        text,
  snapshot_at timestamptz NOT NULL
);

CREATE TABLE crm.dim_customer_history (
  customer_sk bigserial PRIMARY KEY,
  user_id     bigint NOT NULL,
  email       text,
  country     text,
  plan        text,
  valid_from  timestamptz NOT NULL,
  valid_to    timestamptz,
  is_current  boolean NOT NULL
);
