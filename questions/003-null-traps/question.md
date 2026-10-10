---
id: 3
title: NULL traps
level: 1
topics: NULL, three-valued logic, NOT IN, IS DISTINCT FROM
tables: users
---
Marketing needs two quick numbers, both about **real users** only:

1. `not_from_ads`: users whose `referral_source` is anything other than `'ads'`. Users whose source is unknown (`NULL`) **count as not from ads**.
2. `never_referred_anyone`: users whose `user_id` never appears in `users.referred_by` (nobody signed up through them).

**Expected columns:** `not_from_ads`, `never_referred_anyone`. Exactly one row.

Two "obvious" one-liners give wrong answers here. Work out why before moving on.

## Hints
- `NULL <> 'ads'` is not true. It is `NULL`, and `WHERE` keeps only rows where the condition is true. Look up `IS DISTINCT FROM`.
- `x NOT IN (1, 2, NULL)` can never be true: SQL can't rule out that `x` equals the unknown value. What does `referred_by` contain for most users?
- Two scalar subqueries in one `SELECT` give you a one-row result: `SELECT (SELECT ...) AS a, (SELECT ...) AS b;`
