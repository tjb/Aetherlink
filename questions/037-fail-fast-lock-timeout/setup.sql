-- Lab for Q037: the import table and migration role from Q035, with no timeouts configured.
CREATE SCHEMA IF NOT EXISTS lab;
CREATE TABLE IF NOT EXISTS lab.import_batches (
  id          bigserial PRIMARY KEY,
  source      text NOT NULL,
  payload     jsonb NOT NULL,
  imported_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO lab.import_batches (source, payload)
SELECT 'partner_feed', jsonb_build_object('row', g)
FROM generate_series(1, 5000) g
WHERE NOT EXISTS (SELECT 1 FROM lab.import_batches);

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_migrator') THEN
    CREATE ROLE app_migrator NOLOGIN;
  END IF;
END $$;
GRANT USAGE ON SCHEMA lab TO app_migrator;
GRANT SELECT, INSERT, UPDATE, DELETE ON lab.import_batches TO app_migrator;
ALTER ROLE app_migrator RESET ALL;
