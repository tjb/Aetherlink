-- Q036 · DELETE vs TRUNCATE on disk
--
-- DELETE (MVCC): every row version stays in the file, stamped with the deleting transaction's
-- id in xmax. Readers with older snapshots still see the rows, and ROLLBACK just "forgets" the
-- stamp. Size before = size after. The space is only reclaimed by VACUUM once no snapshot can
-- see those versions any more.
--
-- VACUUM (plain): removes dead tuples, records the free space in the free space map so new rows
-- can reuse it, and *truncates empty pages off the end of the file*. Here every page is empty,
-- so the file shrinks to 0 bytes in place (same filenode). That last step briefly needs an
-- ACCESS EXCLUSIVE lock and is skipped if it can't get it. In the middle of a table, freed
-- space is reused but never returned to the OS.
--
-- TRUNCATE: allocates a NEW empty file (new relfilenode) and schedules the old one for deletion
-- at COMMIT. That's why it's instant, why it can still be rolled back, and why it needs an
-- ACCESS EXCLUSIVE lock. It's also why it isn't MVCC-safe. Try it with two psql sessions:
--   A: BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT 1;     -- take a snapshot
--   B: TRUNCATE lab.events_b;                             -- doesn't block: A never touched it
--   A: SELECT count(*) FROM lab.events_b;  -- 0, although A's snapshot predates the TRUNCATE!
-- Do the same with DELETE and A keeps seeing every row until it commits.
--
-- VACUUM FULL / CLUSTER rewrite the whole table into a new file (new filenode, ACCESS EXCLUSIVE
-- for the duration). It's the only way to give back space in the *middle* of a table, and the
-- most disruptive. pg_repack does the same online.
--
-- Look at the files themselves:
--   SELECT pg_relation_filepath('lab.events_a');
--   docker exec sql-dojo-db ls -l /var/lib/postgresql/data/<that path>*
DELETE FROM lab.events_a;
TRUNCATE lab.events_b;

SELECT table_name, filenode AS old_filenode, pg_relation_filenode(('lab.' || table_name)::regclass) AS filenode,
       pg_size_pretty(bytes) AS old_size, pg_size_pretty(pg_relation_size(('lab.' || table_name)::regclass)) AS size
FROM lab.files_before;

VACUUM (VERBOSE) lab.events_a;

SELECT pg_relation_filenode('lab.events_a') AS filenode, pg_relation_size('lab.events_a') AS bytes;
