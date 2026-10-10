-- Run the job's UPDATE inside a transaction, measure HOT updates, roll back.
BEGIN;
CREATE TEMP TABLE hot_before ON COMMIT DROP AS
  SELECT n_tup_upd, n_tup_hot_upd FROM pg_stat_xact_user_tables
  WHERE relid = 'lab.product_stats'::regclass;
UPDATE lab.product_stats SET views = views + 1 WHERE product_id % 20 = 0;
WITH delta AS (
  SELECT a.n_tup_upd - coalesce(b.n_tup_upd, 0) AS upd,
         a.n_tup_hot_upd - coalesce(b.n_tup_hot_upd, 0) AS hot
  FROM pg_stat_xact_user_tables a
  LEFT JOIN hot_before b ON true
  WHERE a.relid = 'lab.product_stats'::regclass
)
SELECT 'the primary key is still there' AS check,
       EXISTS (SELECT 1 FROM pg_index WHERE indrelid = 'lab.product_stats'::regclass AND indisprimary) AS ok,
       '' AS detail
UNION ALL
SELECT 'product_stats_updated_idx is still there',
       to_regclass('lab.product_stats_updated_idx') IS NOT NULL, ''
UNION ALL
SELECT 'at least 90% of the job''s updates are HOT',
       upd > 0 AND hot >= 0.9 * upd,
       format('%s of %s updates were HOT (%s%%)', hot, upd, round(100.0 * hot / nullif(upd, 0)))
FROM delta;
ROLLBACK;
