---
id: 2
title: Customers who never ordered
level: 1
topics: anti-join, NOT EXISTS, LEFT JOIN, FILTER
tables: users, orders
decimals: 1
---
Growth thinks some countries have lots of sign-ups who never buy anything.

**For each country, how many real users are there, how many of them have never placed a single order (any status), and what percentage is that?**

**Expected columns:** `country`, `users`, `never_ordered`, `pct_never_ordered` (percentage, 1 decimal, e.g. `61.3`). One row per country, ordered by `pct_never_ordered` descending.

## Hints
- This is an *anti-join*: rows in A with no match in B. Postgres offers three spellings: `NOT EXISTS (...)`, `LEFT JOIN ... WHERE b.key IS NULL`, and `NOT IN (...)`. Learn the first two. The third has a nasty NULL trap (see Q003).
- `count(*) FILTER (WHERE condition)` counts only the rows matching the condition, which lets you compute several counts in one pass.
- Watch out for integer division: `3 / 4` is `0` in SQL. Write `100.0 * a / b`.
