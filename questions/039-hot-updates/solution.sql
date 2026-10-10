-- Q039 · Make updates HOT
--
-- Two things blocked HOT:
--   1. product_stats_views_idx indexes the column the job changes, so every update needs a new
--      index entry. It was never used (idx_scan = 0), so it was pure cost: every index on a
--      table makes every write more expensive and bloats on updates. Unused indexes are
--      worth hunting (pg_stat_user_indexes.idx_scan, ideally over weeks, on primary AND
--      replicas).
--   2. fillfactor = 100 packs every page full, so a new row version has to go to another
--      page, which also means new index entries. fillfactor = 90 keeps 10% of each page free for
--      updates. ALTER TABLE only records the setting: VACUUM FULL (or CLUSTER) rewrites the
--      table so existing pages get the free space too. (It needs an ACCESS EXCLUSIVE lock for
--      the whole rewrite. Do it in a quiet moment, or use pg_repack.)
--
-- Why it matters: HOT updates touch only the heap page, write less WAL, create no index bloat,
-- and their dead versions can be cleaned up page by page during normal reads ("pruning")
-- without waiting for VACUUM. For update-heavy tables (counters, queues, sessions), HOT ratio
-- is one of the most important health metrics:
--   SELECT relname, n_tup_upd, n_tup_hot_upd, round(100.0 * n_tup_hot_upd / nullif(n_tup_upd, 0)) AS hot_pct
--   FROM pg_stat_user_tables ORDER BY n_tup_upd DESC;
SELECT indexrelname, idx_scan FROM pg_stat_user_indexes WHERE schemaname = 'lab' AND relname = 'product_stats';

DROP INDEX lab.product_stats_views_idx;
ALTER TABLE lab.product_stats SET (fillfactor = 90);
VACUUM FULL lab.product_stats;

BEGIN;
UPDATE lab.product_stats SET views = views + 1 WHERE product_id % 20 = 0;
SELECT n_tup_upd, n_tup_hot_upd FROM pg_stat_xact_user_tables WHERE relname = 'product_stats';
ROLLBACK;
