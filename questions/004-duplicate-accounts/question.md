---
id: 4
title: Duplicate accounts
level: 1
topics: GROUP BY, HAVING, string normalisation, array_agg
tables: users
---
Some people signed up more than once. Their emails differ only in **upper/lower case or surrounding whitespace** (`Maria.Garcia12@Gmail.Com`, `maria.garcia12@gmail.com `).

**Find every normalised email (`lower(trim(email))`) that belongs to more than one real user.**

**Expected columns:**
- `email`: the normalised email
- `accounts`: how many accounts share it
- `first_user_id`: the smallest `user_id` among them (we'll keep that one)
- `other_user_ids`: the remaining `user_id`s as an **array** (`bigint[]`), ascending, e.g. `{4512,90210}`

Order by `accounts` descending, then `email`.

## Hints
- Group by an expression: `GROUP BY lower(trim(email))`.
- `HAVING` filters groups after aggregation. `WHERE` filters rows before it.
- `array_agg(x ORDER BY x)` builds a sorted array. Arrays are 1-indexed and support slices: `arr[2:]`.
