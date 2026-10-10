-- Lab for Q036: two identical tables, autovacuum off, original files recorded.
CREATE SCHEMA IF NOT EXISTS lab;
DROP TABLE IF EXISTS lab.events_a, lab.events_b, lab.files_before;
CREATE TABLE lab.events_a WITH (autovacuum_enabled = false) AS
  SELECT * FROM events WHERE occurred_at >= '2025-12-01';
CREATE TABLE lab.events_b WITH (autovacuum_enabled = false) AS
  SELECT * FROM events WHERE occurred_at >= '2025-12-01';
CREATE TABLE lab.files_before AS
  SELECT c.relname AS table_name,
         pg_relation_filenode(c.oid) AS filenode,
         pg_relation_filepath(c.oid) AS filepath,
         pg_relation_size(c.oid)     AS bytes
  FROM pg_class c
  WHERE c.oid IN ('lab.events_a'::regclass, 'lab.events_b'::regclass);
