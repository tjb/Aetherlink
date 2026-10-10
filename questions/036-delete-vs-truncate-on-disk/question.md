---
id: 36
title: DELETE vs TRUNCATE on disk
level: 6
kind: state
topics: MVCC, dead tuples, VACUUM, relfilenode, storage
tables: lab.events_a, lab.events_b, lab.files_before
---
Every table is stored as one or more files under Postgres's data directory. The lab gives you two
identical copies of December's events, **`lab.events_a`** and **`lab.events_b`**, with autovacuum
switched off so nothing happens behind your back. Their original file numbers and sizes are saved
in `lab.files_before`.

Investigate what each command does to the files, using `pg_relation_filenode('lab.events_a')`
(which file), `pg_relation_size(...)` (its size in bytes) and `pg_relation_filepath(...)` (its path
inside the data directory):

1. Empty `lab.events_a` with **`DELETE`**, and `lab.events_b` with **`TRUNCATE`**. Compare files
   and sizes before and after. Which table still takes up disk space? Which one has a different
   file?
2. `lab.events_a` now has zero visible rows and still occupies tens of megabytes. **Shrink it to
   0 bytes without changing its file**: no `TRUNCATE`, no `VACUUM FULL`, no `CLUSTER`.

Run statements from the editor (`Ctrl+R` runs everything in it, statement by statement, with
autocommit) or from `./dojo psql`. Then check. Messed up? *Reset this lab* in the command palette
(`./dojo lab-reset 36`).

The check verifies: both tables are empty, `events_b` has a new file, and `events_a` has its
original file at 0 bytes.

## Hints
- `DELETE` doesn't remove anything from the file. It stamps each row version as deleted by your transaction (`xmax`), because other transactions may still need to see it. The row versions become *dead tuples*: `SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = 'events_a'` (statistics arrive a moment after your session ends, so run it separately).
- Something has to clean up dead tuples once no transaction can see them any more. That's normally autovacuum's job, but it's off for these tables.
- Plain `VACUUM` makes dead space reusable *inside* the file, and it can also cut off empty pages at the *end* of the file. When every page is empty, that's the whole file.
