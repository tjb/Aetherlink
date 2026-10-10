-- Q054 · An audit trail with triggers
--
-- Why triggers: the log is written by the database, in the same transaction as the change, for
-- every client (the app, a migration, someone in psql at 2 a.m.). Roll back the change and the
-- log entry disappears with it; commit, and both are there. An audit trail written by the
-- application misses every change made outside the application.
--
-- The details that matter:
--  * Row-level AFTER triggers see OLD and NEW. to_jsonb(OLD) captures the whole row, so the
--    log survives schema changes (a new column simply shows up in the JSON).
--  * A WHEN clause on the trigger filters before the function is even called. IS DISTINCT FROM
--    (not <>) because columns can be NULL. Subtracting a key from jsonb ignores noisy columns.
--  * TRUNCATE doesn't fire DELETE triggers. It removes the table's files wholesale (Q034, Q036)
--    instead of deleting rows, so there are no rows to report. Only a statement-level
--    ON TRUNCATE trigger notices, and it can't see what was removed. If an audit trail must be
--    complete, revoke TRUNCATE from the application roles (Level 6).
--  * Triggers cost something on every write. For a high-volume table, logical decoding
--    (change data capture: Debezium, pg_recvlogical, logical replication) reads the same
--    changes from the WAL instead, with no write overhead and no way to bypass it.
--  * CREATE OR REPLACE everywhere, so running this twice doesn't create a second trigger.
CREATE OR REPLACE FUNCTION audit.log_product_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'TRUNCATE' THEN
    INSERT INTO audit.product_log (op) VALUES ('TRUNCATE');
  ELSIF TG_OP = 'INSERT' THEN
    INSERT INTO audit.product_log (op, product_id, new_row) VALUES ('INSERT', NEW.product_id, to_jsonb(NEW));
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO audit.product_log (op, product_id, old_row, new_row)
    VALUES ('UPDATE', NEW.product_id, to_jsonb(OLD), to_jsonb(NEW));
  ELSE
    INSERT INTO audit.product_log (op, product_id, old_row) VALUES ('DELETE', OLD.product_id, to_jsonb(OLD));
  END IF;
  RETURN NULL;  -- the return value of an AFTER trigger is ignored
END $$;

CREATE OR REPLACE TRIGGER products_audit_ins_del
AFTER INSERT OR DELETE ON audit.products
FOR EACH ROW EXECUTE FUNCTION audit.log_product_change();

CREATE OR REPLACE TRIGGER products_audit_upd
AFTER UPDATE ON audit.products
FOR EACH ROW
WHEN (to_jsonb(OLD) - 'view_count' IS DISTINCT FROM to_jsonb(NEW) - 'view_count')
EXECUTE FUNCTION audit.log_product_change();

CREATE OR REPLACE TRIGGER products_audit_truncate
AFTER TRUNCATE ON audit.products
FOR EACH STATEMENT EXECUTE FUNCTION audit.log_product_change();
