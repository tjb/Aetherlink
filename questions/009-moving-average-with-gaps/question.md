---
id: 9
title: Moving average with gaps
level: 2
topics: generate_series, gap filling, moving average, ROWS frames, filter after window
tables: users
decimals: 2
---
Spain (`country = 'ES'`) is a small market, so some days have no sign-ups at all.

**For every day of Q1 2025 (Jan 1 – Mar 31), report the number of real users from Spain who signed up that day and the trailing 7-day average.**

- Days with zero sign-ups **must appear** with `signups = 0`.
- The 7-day average covers the day itself and the 6 days before it. So **Jan 1's average includes Dec 26–31, 2024**.
- A "day" is the UTC date of `signup_at`.

**Expected columns:** `day` (date), `signups`, `avg_7d` (2 decimals). 90 rows ordered by day.

## Hints
- `GROUP BY` can't invent days that have no rows. Generate a calendar with `generate_series(date '2024-12-26', date '2025-03-31', interval '1 day')` and `LEFT JOIN` the counts onto it.
- `avg(x) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)` is a trailing 7-row average. It's only a 7-*day* average if every day has a row (hint 1).
- If you put `WHERE day >= '2025-01-01'` in the same query as the window function, Jan 1 can't see December, because `WHERE` runs before windows. Filter in an outer query.
