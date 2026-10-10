---
id: 35
title: Migration without TRUNCATE
level: 6
kind: script
run_as: app_migrator
topics: privileges, TRUNCATE vs DELETE, sequences, migrations
tables: lab.import_batches
---
Migrations run as the role **`app_migrator`**. It can `SELECT/INSERT/UPDATE/DELETE` on
`lab.import_batches` and use and update its id sequence, and **nothing else**. This migration
passed review, then failed in production:

```sql
TRUNCATE lab.import_batches RESTART IDENTITY;
INSERT INTO lab.import_batches (source, payload)
VALUES ('manual', '{"note": "fresh start"}');
```

```
ERROR:  permission denied for table import_batches
```

The DBA won't grant `TRUNCATE`. **Rewrite the migration so that, run as `app_migrator`, it
leaves the table in exactly the state the original intended:**

- the table contains exactly one row: `source = 'manual'`, `payload = {"note": "fresh start"}`;
- that row has `id = 1`, and the next insert will get `id = 2` (the identity was restarted).

Your answer file is the migration script (several statements are fine). Each check resets the
lab, runs your script as `app_migrator` inside a transaction, inspects the result and rolls back.
Try the original first and watch it fail.

## Hints
- TRUNCATE is its own privilege in Postgres, separate from DELETE. What does `DELETE FROM lab.import_batches;` need?
- `RESTART IDENTITY` resets the sequence behind `id`. `ALTER SEQUENCE ... RESTART` requires *owning* the sequence, but `setval()` only needs `UPDATE` on it.
- `setval(seq, 1, false)` means "the next `nextval()` returns 1". `pg_get_serial_sequence('lab.import_batches', 'id')` finds the sequence name for you.
