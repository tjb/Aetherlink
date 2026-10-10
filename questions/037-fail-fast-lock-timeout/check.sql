-- Settings stored for the role (in any database or for this one), normalised to milliseconds.
CREATE FUNCTION pg_temp.to_ms(v text) RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN v ~ '^\s*\d+(\.\d+)?\s*$' THEN v::numeric
    WHEN v ~* '^\s*\d+(\.\d+)?\s*(ms|s|min|h|d)\s*$' THEN
      (regexp_match(v, '[\d.]+'))[1]::numeric *
      CASE lower((regexp_match(v, '(ms|min|s|h|d)\s*$', 'i'))[1])
        WHEN 'ms' THEN 1 WHEN 's' THEN 1000 WHEN 'min' THEN 60000 WHEN 'h' THEN 3600000 ELSE 86400000 END
  END $$;

WITH settings AS (
  SELECT split_part(c, '=', 1) AS name, substr(c, strpos(c, '=') + 1) AS value
  FROM pg_db_role_setting s
  CROSS JOIN LATERAL unnest(s.setconfig) AS c
  WHERE s.setrole = (SELECT oid FROM pg_roles WHERE rolname = 'app_migrator')
    AND s.setdatabase IN (0, (SELECT oid FROM pg_database WHERE datname = current_database()))
)
SELECT 'role app_migrator exists' AS check,
       EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_migrator') AS ok,
       '' AS detail
UNION ALL
SELECT 'app_migrator waits at most 3s for a lock',
       coalesce((SELECT pg_temp.to_ms(value) = 3000 FROM settings WHERE name = 'lock_timeout' LIMIT 1), false),
       coalesce((SELECT 'lock_timeout = ' || value FROM settings WHERE name = 'lock_timeout' LIMIT 1), 'lock_timeout not set for the role')
UNION ALL
SELECT 'app_migrator statements stop after 10 minutes',
       coalesce((SELECT pg_temp.to_ms(value) = 600000 FROM settings WHERE name = 'statement_timeout' LIMIT 1), false),
       coalesce((SELECT 'statement_timeout = ' || value FROM settings WHERE name = 'statement_timeout' LIMIT 1), 'statement_timeout not set for the role')
