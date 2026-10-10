---
id: 14
title: Sessionization
level: 3
topics: sessionization, LAG, running SUM as a group id, gaps and islands
tables: events, users
decimals: 1
---
The `events` table has no session id. Product analytics needs sessions anyway, so you'll have to rebuild them.

**Definition:** a session is a run of events by the same logged-in user where each event comes **at most 30 minutes** after the previous one. A gap of more than 30 minutes starts a new session.

- Only events from **December 2025** (`occurred_at` in `[2025-12-01, 2026-01-01)`). Treat Dec 1 00:00 as a hard boundary: each user's first December event starts a session.
- Only events with a `user_id`, from real users.
- Order a user's events by `occurred_at`, then `event_id`. Count every event row, including duplicates.

**For each device, how many sessions were there, how many events per session on average, and how long did sessions last on average?** A session's device is the device of its first event. Its duration is last event minus first event, in minutes.

**Expected columns:** `device`, `sessions`, `avg_events` (1 decimal), `avg_minutes` (1 decimal). Ordered by device.

## Hints
- Step 1: `lag(occurred_at) OVER (PARTITION BY user_id ORDER BY occurred_at, event_id)` gives each event the previous event's time.
- Step 2: flag session starts: `1` when there's no previous event or the gap is `> interval '30 minutes'`, else `0`.
- Step 3: a running `sum(flag) OVER (PARTITION BY user_id ORDER BY ...)` numbers the sessions 1, 2, 3, …. Now `GROUP BY user_id, session_no`. This "flag + running sum" trick solves a whole family of problems.
- The device of the first event: `(array_agg(device ORDER BY occurred_at, event_id))[1]`, or `first_value()` in a window.
