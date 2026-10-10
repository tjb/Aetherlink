-- Q053 · Overwrite one partition
--
-- Files in a lake are immutable, so "delete these rows" means "rewrite the files that contain
-- them". Partitioning limits the blast radius: rewrite one month, not three years. This is
-- what Spark calls dynamic partition overwrite.
--
-- Doing it safely by hand: stage the new version, then replace. Even so, between deleting the
-- old files and finishing the new ones, a reader can see a half-written partition, and there's
-- no rollback if the job dies halfway. That gap is exactly why table formats exist. Apache
-- Iceberg, Delta Lake and Hudi add a transaction log/metadata layer over the files: a commit
-- atomically swaps which files make up the table, readers see either the old or the new
-- snapshot, you get time travel to earlier snapshots, and deletes can be written as small
-- "delete files" that are merged on read and compacted later instead of rewriting everything.
--
-- Try the tempting shortcut: read the whole table and COPY it back with PARTITION_BY + OVERWRITE.
-- OVERWRITE deletes the target folder before the query has read its source, and the files are
-- gone. Stage first, always.
--
-- (NOT IN is safe here only because event_id in the corrections file is never NULL. NOT EXISTS
-- would be safe regardless. See Q003.)
COPY (
  SELECT e.event_id, e.occurred_at, e.user_id, e.device, e.event_type, e.product_id, e.properties
  FROM read_parquet('lake/lab/events_q4/month=2025-11/*.parquet') e
  WHERE NOT EXISTS (SELECT 1 FROM read_csv('lake/raw/corrections/bot_events_2025-11.csv') b
                    WHERE b.event_id = e.event_id)
) TO 'lake/lab/staging_2025-11.parquet' (FORMAT parquet, COMPRESSION zstd);

COPY (SELECT * FROM read_parquet('lake/lab/staging_2025-11.parquet'))
TO 'lake/lab/events_q4/month=2025-11' (FORMAT parquet, COMPRESSION zstd, PER_THREAD_OUTPUT true, OVERWRITE true);

SELECT month, count(*) AS events
FROM read_parquet('lake/lab/events_q4/*/*.parquet', hive_partitioning = true)
GROUP BY month ORDER BY month;
