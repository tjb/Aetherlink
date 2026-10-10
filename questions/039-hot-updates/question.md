---
id: 39
title: Make updates HOT
level: 6
kind: state
topics: MVCC, HOT updates, fillfactor, index write amplification, unused indexes
tables: lab.product_stats
---
`lab.product_stats` holds one row of counters per product. A background job bumps them all day:

```sql
UPDATE lab.product_stats SET views = views + 1 WHERE product_id % 20 = 0;
```

In Postgres an `UPDATE` never changes a row in place. It writes a **new row version** and
normally also inserts a new entry into **every index** on the table. The exception is a
**HOT (heap-only tuple) update**, which skips the indexes completely. It's possible only when:

1. none of the columns the UPDATE changes is indexed, and
2. the new version fits on the **same page** as the old one.

Right now none of this job's updates are HOT. **Make the job's UPDATE at least 90% HOT** without
changing the statement. Two constraints:

- keep the primary key, and keep `product_stats_updated_idx` (the dashboard uses it);
- the check runs the job's UPDATE in a transaction and rolls it back, so the data doesn't matter.

Measure it yourself:

```sql
BEGIN;
UPDATE lab.product_stats SET views = views + 1 WHERE product_id % 20 = 0;
SELECT n_tup_upd, n_tup_hot_upd FROM pg_stat_xact_user_tables WHERE relname = 'product_stats';
ROLLBACK;
```

## Hints
- Which indexes exist (`\d lab.product_stats`), and which have ever been used? `SELECT indexrelname, idx_scan FROM pg_stat_user_indexes WHERE schemaname = 'lab'`.
- The table was created with `fillfactor = 100`: every page is packed full, so a new row version can never fit next to the old one. A lower fillfactor leaves free space in each page...
- ...but `ALTER TABLE ... SET (fillfactor = ...)` only affects pages written from now on. Existing pages stay full until the table is rewritten (`VACUUM FULL` or `CLUSTER`).
