---
id: 45
title: Late-arriving data
level: 7
kind: pipeline
plan: setup, batch_1, answer, answer, batch_2, answer, answer, batch_3, answer, answer, check
topics: incremental processing, late-arriving data, exactly-once, idempotency, upserts, watermarks
tables: stream.landing_events, stream.daily_event_counts
---
December's clickstream arrives in **batches**. Each batch replaces the landing table
`stream.landing_events` (`batch_id`, `event_id`, `occurred_at`, `event_type`), so it only ever
holds **the newest batch**. Events also **arrive late**: a batch mostly contains recent days, plus
stragglers from days that earlier batches already covered.

Maintain **`stream.daily_event_counts`** (`day`, `event_type`, `events`; primary key on
`day, event_type`) so that after every load it holds the number of events delivered so far for
each UTC day and event type.

- You **can't** recompute from scratch: older batches are gone from the landing table.
- Late events must be **added** to the days they belong to.
- The checker runs your load **twice after every batch** (jobs get retried). A batch must be
  counted exactly once.

You may create any extra tables you need in schema `stream`. It's wiped when the lab resets.

## Hints
- `INSERT ... ON CONFLICT (day, event_type) DO UPDATE SET events = d.events + EXCLUDED.events` adds counts into existing days. On its own it's not idempotent: a retry adds the batch again.
- Remember what you've processed: a small `stream.loaded_batches (batch_id PRIMARY KEY)` ledger. Only count landing rows whose batch isn't in the ledger, and record the batch **in the same transaction** as the counts, so a crash can't leave one without the other.
- A single statement is atomic: `WITH new AS (INSERT INTO ledger ... ON CONFLICT DO NOTHING RETURNING batch_id) INSERT INTO counts ... WHERE batch_id IN (SELECT batch_id FROM new)`.
