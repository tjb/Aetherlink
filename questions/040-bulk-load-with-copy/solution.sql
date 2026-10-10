-- Q040 · Bulk load with COPY
--
-- The ELT pattern: Extract (the partner did it), Load raw text into staging, Transform with SQL.
--
--  * COPY is a bulk protocol: one statement, no per-row round trips, roughly 10-100x faster than
--    INSERTs. COPY ... FROM 'file' runs on the server and needs superuser or
--    pg_read_server_files. psql's \copy streams the file from the client instead.
--  * Staging as text means a malformed value can't abort the load. You find it with SQL
--    afterwards (try: SELECT * FROM stage WHERE total !~ '^[0-9,]+\.[0-9]{2}$').
--  * Empty CSV fields arrive as NULL (unquoted empty = NULL in CSV mode), but whitespace-only
--    fields don't. nullif(trim(x), '') covers both.
--  * Time zones: to_timestamp() parses the digits as session-time (UTC here); casting back to
--    timestamp recovers the wall-clock digits, and AT TIME ZONE 'Europe/Berlin' turns Berlin
--    wall-clock time into the real instant. (Alternative: SET LOCAL timezone = 'Europe/Berlin'.)
--  * Duplicates inside one batch break INSERT ... ON CONFLICT DO UPDATE ("command cannot affect
--    row a second time"), so dedupe first with DISTINCT ON.
--  * Idempotency: TRUNCATE + INSERT inside one transaction is the simplest full refresh, and
--    readers never see an empty table because TRUNCATE is transactional. For an incremental
--    feed, upsert instead.
BEGIN;

CREATE TEMP TABLE stage (
  order_id text, order_date text, customer_email text, country text,
  units text, total text, status text, notes text
) ON COMMIT DROP;

COPY stage FROM '/tmp/dojo_partner_orders.csv' WITH (FORMAT csv, HEADER true);

TRUNCATE partner.orders;

INSERT INTO partner.orders (order_id, ordered_at, customer_email, country, units, total, status, notes)
SELECT DISTINCT ON (order_id::bigint)
       order_id::bigint,
       to_timestamp(order_date, 'DD/MM/YYYY HH24:MI')::timestamp AT TIME ZONE 'Europe/Berlin',
       lower(trim(customer_email)),
       nullif(trim(country), ''),
       units::int,
       replace(total, ',', '')::numeric(12,2),
       lower(trim(status)),
       nullif(trim(notes), '')
FROM stage
ORDER BY order_id::bigint;

COMMIT;
