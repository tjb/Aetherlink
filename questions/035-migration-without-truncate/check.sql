-- Runs (as the superuser) right after your script, in the same transaction.
SELECT 'exactly one row left' AS check,
       count(*) = 1 AS ok,
       format('%s rows', count(*)) AS detail
FROM lab.import_batches
UNION ALL
SELECT 'it is the manual row',
       coalesce((SELECT bool_and(source = 'manual' AND payload = '{"note": "fresh start"}') FROM lab.import_batches), false),
       coalesce(string_agg(format('source=%s payload=%s', source, payload), '; ') || CASE WHEN count(*) = 3 THEN '; ...' ELSE '' END, 'no rows')
FROM (SELECT * FROM lab.import_batches ORDER BY id LIMIT 3) first_rows
UNION ALL
SELECT 'its id is 1',
       coalesce(min(id) = 1 AND max(id) = 1, false),
       coalesce(format('id=%s', min(id)), 'no rows')
FROM lab.import_batches
UNION ALL
SELECT 'the next id will be 2',
       last_value = 1 AND is_called,
       format('sequence last_value=%s is_called=%s', last_value, is_called)
FROM lab.import_batches_id_seq
