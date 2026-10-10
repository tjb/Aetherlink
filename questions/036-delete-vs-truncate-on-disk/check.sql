WITH now_ AS (
  SELECT c.relname AS table_name, pg_relation_filenode(c.oid) AS filenode, pg_relation_size(c.oid) AS bytes
  FROM pg_class c
  WHERE c.oid IN ('lab.events_a'::regclass, 'lab.events_b'::regclass)
), cmp AS (
  SELECT n.table_name, n.filenode, n.bytes, b.filenode AS old_filenode, b.bytes AS old_bytes
  FROM now_ n JOIN lab.files_before b USING (table_name)
)
SELECT 'events_a is empty' AS check,
       NOT EXISTS (SELECT 1 FROM lab.events_a) AS ok,
       '' AS detail
UNION ALL
SELECT 'events_b is empty', NOT EXISTS (SELECT 1 FROM lab.events_b), ''
UNION ALL
SELECT 'events_b got a brand-new file (TRUNCATE)', filenode <> old_filenode,
       format('filenode %s -> %s', old_filenode, filenode)
FROM cmp WHERE table_name = 'events_b'
UNION ALL
SELECT 'events_a still uses its original file', filenode = old_filenode,
       format('filenode %s -> %s', old_filenode, filenode)
FROM cmp WHERE table_name = 'events_a'
UNION ALL
SELECT 'events_a takes 0 bytes on disk', bytes = 0,
       format('%s -> %s', pg_size_pretty(old_bytes), pg_size_pretty(bytes))
FROM cmp WHERE table_name = 'events_a'
