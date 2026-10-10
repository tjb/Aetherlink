-- Lab for Q038: five roles with direct grants and memberships (Postgres 16+ grant syntax).
DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['analyst', 'app_rw', 'etl', 'oncall'] LOOP
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN', r);
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'intern') THEN
    CREATE ROLE intern NOLOGIN NOINHERIT;
  END IF;
END $$;

-- start from a clean slate on the dataset tables
REVOKE ALL ON users, categories, products, product_prices, orders, order_items, events, reviews, subscriptions
  FROM analyst, app_rw, etl, oncall, intern;
REVOKE app_rw FROM etl, intern;
REVOKE etl, analyst FROM oncall;

GRANT SELECT ON users, categories, products, product_prices, orders, order_items, events, reviews, subscriptions
  TO analyst;
GRANT SELECT, INSERT, UPDATE, DELETE ON orders, order_items, events, reviews TO app_rw;
GRANT TRUNCATE ON events TO etl;
GRANT DELETE ON users TO oncall;

GRANT app_rw TO etl WITH INHERIT TRUE;
GRANT etl TO oncall WITH INHERIT TRUE;
GRANT analyst TO oncall WITH INHERIT TRUE;
GRANT app_rw TO intern WITH INHERIT FALSE;
