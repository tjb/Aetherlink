-- Q044 · Slowly changing dimension
--
-- SCD types, briefly:
--   type 1: overwrite (no history; fine for fixing typos)
--   type 2: new row per version with validity dates (full history; this question)
--   type 3: keep "previous value" columns (one step of history)
--
-- Order matters: close the changed versions first, then insert every customer who has no
-- current row. That one INSERT covers both brand-new customers and the ones just closed.
-- Run it again with the same snapshot and both statements find nothing to do: idempotent.
--
-- Facts join to the version that was valid when the event happened:
--   JOIN crm.dim_customer_history d
--     ON d.user_id = f.user_id AND f.ordered_at >= d.valid_from
--    AND (d.valid_to IS NULL OR f.ordered_at < d.valid_to)
-- or, better, store customer_sk on the fact row at load time so nobody has to.
--
-- Gotchas: snapshots that arrive out of order (guard with snapshot_at > valid_from), the same
-- customer twice in one snapshot (dedupe first), and deletions (close the current row and keep
-- it closed; that's a "tombstone"). dbt's "snapshots" feature generates exactly this logic.
UPDATE crm.dim_customer_history d
SET valid_to = s.snapshot_at,
    is_current = false
FROM crm.customers s
WHERE d.user_id = s.user_id
  AND d.is_current
  AND (d.email, d.country, d.plan) IS DISTINCT FROM (s.email, s.country, s.plan);

INSERT INTO crm.dim_customer_history (user_id, email, country, plan, valid_from, valid_to, is_current)
SELECT s.user_id, s.email, s.country, s.plan, s.snapshot_at, NULL, true
FROM crm.customers s
WHERE NOT EXISTS (SELECT 1 FROM crm.dim_customer_history d
                  WHERE d.user_id = s.user_id AND d.is_current);
