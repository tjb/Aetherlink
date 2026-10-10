---
id: 15
title: Ordered conversion funnel
level: 3
topics: funnels, conditional joins, MIN per group, UNION ALL, LAG
tables: events, users
decimals: 1
---
**Build the November 2025 purchase funnel: how many user-days reached each step, in order?**

The unit is a **user-day**: one logged-in real user on one UTC date in November 2025. A user-day reaches:

1. **product_view** if it has any `product_view` event;
2. **add_to_cart** if it has an `add_to_cart` event *strictly after* its first step-1 event;
3. **checkout_started** if it has a `checkout_started` event strictly after its first qualifying step-2 event;
4. **purchase** if it has a `purchase` event strictly after its first qualifying step-3 event.

Steps must happen in order and on the same day. An `add_to_cart` *before* any product view that day does not count.

**Expected columns:** `step` (1–4), `event_type`, `user_days`, `pct_of_previous` (vs the previous step, `NULL` for step 1), `pct_of_step1` (vs step 1, so 100.0 for step 1). 1 decimal. 4 rows ordered by step.

## Hints
- Compute the step-1 time per user-day: `min(occurred_at)` grouped by `user_id, occurred_at::date`.
- Step 2 joins step 1 to `add_to_cart` events of the same user and day with `occurred_at > step1_time`, then takes `min()` again. Steps 3 and 4 follow the same pattern. If it's slow, `EXPLAIN ANALYZE` it and compare estimated vs actual rows.
- A join-free alternative: window aggregates accept `FILTER`, so `min(occurred_at) FILTER (WHERE event_type = 'add_to_cart' AND occurred_at > t1) OVER (PARTITION BY user_id, day)` stamps every row with the step-2 time. Layer one subquery per step.
- Stack the four counts with `UNION ALL`, then use `lag()` and `first_value()` over `step` for the percentages.
