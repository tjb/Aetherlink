---
id: 16
title: Cohort retention
level: 3
topics: cohorts, retention, month arithmetic, CROSS JOIN, zero-filling
tables: users, events
decimals: 1
---
**Build a monthly retention table for the January–June 2025 sign-up cohorts.**

- A user's cohort is the month of their `signup_at`. Real users who signed up between 2025-01-01 and 2025-06-30 only.
- A user is **active** in a month if they have at least one event with their `user_id` in that month.
- `month_number` 0 is the sign-up month itself, 1 is the next month, … up to 6.
- Every cohort × month_number combination must appear (42 rows), even if `active_users` is 0.

**Expected columns:** `cohort_month` (date), `cohort_size`, `month_number`, `active_users`, `retention_pct` (`active_users` as % of `cohort_size`, 1 decimal). Ordered by `cohort_month`, `month_number`.

## Hints
- Months between two first-of-month dates: `(extract(year FROM a) - extract(year FROM b)) * 12 + extract(month FROM a) - extract(month FROM b)`.
- First reduce events to distinct `(user_id, month)` pairs. Retention never needs more than "was active that month".
- To guarantee all 42 rows, build the grid first (`cohorts CROSS JOIN generate_series(0, 6)`) and `LEFT JOIN` the activity counts onto it.
