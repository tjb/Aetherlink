---
id: 17
title: Longest daily streak
level: 3
topics: gaps and islands, ROW_NUMBER, date arithmetic, DISTINCT ON
tables: events, users
---
A few devoted customers open the app almost every day. Marketing wants to send them a thank-you.

**For each real user, find their longest run of consecutive UTC days in 2025 with at least one event under their `user_id`. Return the 10 users with the longest streaks.**

- If a user has several streaks of the same maximum length, report the earliest one.

**Expected columns:** `user_id`, `streak_days`, `streak_start` (date), `streak_end` (date). 10 rows ordered by `streak_days` descending, then `user_id`.

## Hints
- First reduce events to distinct `(user_id, day)` rows.
- The "gaps and islands" trick: for consecutive days, `day - row_number()` is the same constant. `2025-03-05 - 1`, `2025-03-06 - 2` and `2025-03-07 - 3` all give `2025-03-04`. Group by that constant.
- `date - integer` is a date in Postgres. Cast `row_number()` (a bigint) with `::int`.
