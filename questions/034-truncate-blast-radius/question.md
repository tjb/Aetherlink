---
id: 34
title: TRUNCATE blast radius
level: 6
topics: TRUNCATE CASCADE, foreign keys, system catalogs, recursive CTEs, cycles
tables: pg_constraint, pg_class
---
A teammate wants to reset a staging database with:

```sql
TRUNCATE users CASCADE;
```

`CASCADE` means "also truncate every table with a foreign key to a truncated table", and that
applies recursively. Before anyone runs it, **find out exactly which tables it would empty** by
querying the system catalogs.

- Foreign keys live in `pg_constraint` (`contype = 'f'`): `conrelid` is the referencing (child)
  table and `confrelid` the referenced (parent) table. Both are `regclass`-compatible OIDs.
- `hops` = the number of foreign keys between `users` and that table along the *shortest* path.
  `users` itself is 0.

**Expected columns:** `table_name` (as `regclass::text` prints it), `hops`. Ordered by `hops`, then
`table_name`.

## Hints
- Start the recursion at `'users'::regclass`, then repeatedly add every table whose foreign key points at a table you've already found.
- `users.referred_by` references `users`, a cycle. A naive recursive CTE never terminates on it. Track the path (`path || child`, then `WHERE child <> ALL (path)`), or use Postgres 14's `CYCLE ... SET ... USING` clause.
- You can check your answer without losing any data, because TRUNCATE is transactional in Postgres: `BEGIN; TRUNCATE users CASCADE; ROLLBACK;` prints a `NOTICE: truncate cascades to table "..."` for each table. (It takes ACCESS EXCLUSIVE locks while it runs, so never try this on a busy production database.)
