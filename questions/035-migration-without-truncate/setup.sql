-- Lab for Q035: a staging table and a least-privilege migration role.
CREATE SCHEMA IF NOT EXISTS lab;
DROP TABLE IF EXISTS lab.import_batches;
CREATE TABLE lab.import_batches (
  id          bigserial PRIMARY KEY,
  source      text NOT NULL,
  payload     jsonb NOT NULL,
  imported_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO lab.import_batches (source, payload)
SELECT 'partner_feed', jsonb_build_object('row', g)
FROM generate_series(1, 5000) g;

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_migrator') THEN
    CREATE ROLE app_migrator NOLOGIN;
  END IF;
END $$;
GRANT USAGE ON SCHEMA lab TO app_migrator;
GRANT SELECT, INSERT, UPDATE, DELETE ON lab.import_batches TO app_migrator;
GRANT USAGE, SELECT, UPDATE ON SEQUENCE lab.import_batches_id_seq TO app_migrator;
