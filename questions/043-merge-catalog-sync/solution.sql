-- Q043 · Sync a catalog with MERGE
--
-- MERGE lets one statement cover all three cases of a sync:
--   WHEN MATCHED [AND condition]       -> rows in both: update only if something changed
--   WHEN NOT MATCHED [BY TARGET]       -> new in the source: insert
--   WHEN NOT MATCHED BY SOURCE         -> gone from the source: soft delete (Postgres 17+)
--
-- Why "only if changed" matters: updated_at is how downstream jobs find what to reprocess
-- (incremental models, cache invalidation, CDC). Touching unchanged rows makes every row look
-- new every day, and in Postgres it also writes a new row version (Q039) for nothing.
--
-- Why soft delete: other tables reference products, history needs them, and suppliers drop
-- items by accident. A flag plus a timestamp keeps the row and lets it come back.
--
-- Idempotency comes for free: re-running with the same feed finds nothing changed, no new
-- SKUs and nothing newly missing, so no row is touched.
--
-- Before MERGE: INSERT ... ON CONFLICT (sku) DO UPDATE SET ... WHERE (changed), plus a separate
-- UPDATE ... WHERE is_active AND sku NOT IN (SELECT sku FROM feed). ON CONFLICT is atomic
-- against concurrent inserts; MERGE (in Postgres) is not, and can fail with a unique violation
-- if another session inserts the same key mid-flight. For a single-writer batch job, fine.
MERGE INTO supplier.catalog AS c
USING supplier.catalog_feed AS f
   ON c.sku = f.sku
WHEN MATCHED AND (NOT c.is_active OR (c.name, c.price) IS DISTINCT FROM (f.name, f.price)) THEN
  UPDATE SET name = f.name, price = f.price, is_active = true,
             deactivated_at = NULL, updated_at = f.extracted_at
WHEN NOT MATCHED BY TARGET THEN
  INSERT (sku, name, price, is_active, first_seen_at, updated_at)
  VALUES (f.sku, f.name, f.price, true, f.extracted_at, f.extracted_at)
WHEN NOT MATCHED BY SOURCE AND c.is_active THEN
  UPDATE SET is_active = false,
             deactivated_at = (SELECT max(extracted_at) FROM supplier.catalog_feed),
             updated_at     = (SELECT max(extracted_at) FROM supplier.catalog_feed);
