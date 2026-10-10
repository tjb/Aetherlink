-- Q052 · Schema drift
--
-- Schema drift is the everyday reality of ingesting data you don't control. The defensive
-- pattern:
--   1. Read with the union of all schemas (union_by_name) and the widest types. Land it raw.
--   2. Normalise in one place (a silver model): coalesce renamed fields, parse formats
--      explicitly, apply documented defaults (channel = 'web' before it existed).
--   3. Test for the next surprise: unknown columns, new enum values, NULL rates (Q041). A new
--      'marketplace' channel should fail an accepted-values test loudly rather than vanish
--      into "other".
-- Table formats (Iceberg/Delta) track schema evolution explicitly: columns get ids, so renames
-- don't break old files. With plain JSON/CSV/Parquet files, the reader has to cope.
WITH partner AS (
  SELECT order_id,
         ts::TIMESTAMPTZ               AS ts,
         coalesce(amount_usd, total)   AS amount,
         coalesce(channel, 'web')      AS channel
  FROM read_json('lake/raw/partner_orders/*.json', union_by_name = true)
)
SELECT date_trunc('quarter', ts)::DATE AS quarter,
       channel,
       count(*)              AS orders,
       round(sum(amount), 2) AS revenue
FROM partner
GROUP BY ALL
ORDER BY quarter, channel;
