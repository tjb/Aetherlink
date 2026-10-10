---
id: 28
title: Duplicate events
level: 4
topics: deduplication, DISTINCT, NULL-safe comparison, data quality
tables: events
---
The event pipeline is "at least once": sometimes an event is stored twice. A duplicate is a row **identical in every column except `event_id`** (`occurred_at`, `user_id`, `device`, `event_type`, `product_id`, `properties`).

**For each day of December 2025 (UTC), how many raw events were stored, how many remain after removing duplicates, and how many duplicates were there?**

**Expected columns:** `day` (date), `raw_events`, `unique_events`, `duplicate_events`. 31 rows ordered by day.

## Hints
- `SELECT DISTINCT col1, col2, ...` treats NULLs as equal to each other. A self-join `ON a.user_id = b.user_id` does **not**: `NULL = NULL` is NULL. Logged-out events have a NULL `user_id`, and many have a NULL `product_id`.
- If you go the join route, `IS NOT DISTINCT FROM` is the NULL-safe equality operator.
- The deduplication pattern you'll use in pipelines: `row_number() OVER (PARTITION BY <all business columns> ORDER BY event_id) = 1` keeps the first copy.
