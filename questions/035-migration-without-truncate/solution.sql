-- Q035 · Migration without TRUNCATE
--
-- DELETE needs the DELETE privilege, which app_migrator has. Resetting the sequence with
-- setval() needs UPDATE on the sequence. ALTER SEQUENCE ... RESTART would need ownership,
-- and so would TRUNCATE ... RESTART IDENTITY even with the TRUNCATE privilege.
--
-- Same end state, very different mechanics:
--
--                     TRUNCATE                          DELETE (no WHERE)
--   privilege         TRUNCATE                          DELETE
--   lock              ACCESS EXCLUSIVE (blocks reads)   ROW EXCLUSIVE (readers carry on)
--   work              swaps in a new empty file         marks every row dead (xmax), one by one
--   disk space        freed at commit                   file stays the same size until VACUUM (Q036)
--   WAL               tiny                              one record per row (replicas replay it all)
--   triggers          ON TRUNCATE only                  ON DELETE, per row or per statement
--   MVCC              not MVCC-safe: old snapshots      fully MVCC: concurrent readers keep
--                     suddenly see an empty table       seeing the rows until they finish
--   rollback          yes in Postgres (no in MySQL)     yes
--
-- So DELETE is the gentler operation for concurrent users, but for big tables it's slow,
-- bloats the table and floods replicas with WAL. Then the right fix is often to grant TRUNCATE
-- (GRANT TRUNCATE ON lab.import_batches TO app_migrator) or to run migrations as the table
-- owner, rather than rewriting. A missing privilege is a decision someone made. Find out why
-- before working around it.
DELETE FROM lab.import_batches;

SELECT setval(pg_get_serial_sequence('lab.import_batches', 'id'), 1, false);

INSERT INTO lab.import_batches (source, payload)
VALUES ('manual', '{"note": "fresh start"}');
