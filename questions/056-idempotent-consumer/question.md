---
id: 56
title: An idempotent consumer
level: 9
kind: pipeline
plan: setup, answer, answer, deliver_1, parallel:deliver_2*4, check
topics: at-least-once delivery, idempotency, inbox/dedupe tables, out-of-order events, versioning, transactional outbox
tables: inbox.published, inbox.order_status, inbox.customer_totals
---
The order service publishes an event every time an order changes. You consume them to keep two
read models up to date:

- **`inbox.order_status`** (`order_id`, `status`, `version`): each order's **latest** status.
- **`inbox.customer_totals`** (`user_id`, `orders`, `spent`): per customer, how many orders are
  neither cancelled nor returned, and what they cost.

A message looks like this (`amount` is only set on `order_placed`, `order_cancelled` and
`order_returned`, and is the order's full amount):

```json
{"message_id": "ord-1234-v2", "type": "order_shipped", "order_id": 1234, "user_id": 77,
 "version": 2, "status": "shipped", "amount": null, "occurred_at": "..."}
```

Each order's messages have increasing `version`s: `order_placed` (1, `pending`), then
`order_shipped` (2), `order_delivered` (3), `order_returned` (4), or `order_cancelled` (2).

**Write `inbox.handle(msg jsonb) RETURNS void`**, which applies one message. The checker calls it
for every delivery, and the broker is "at least once":
- messages arrive **out of order** (a `delivered` can come before its `shipped`, even before its
  `placed`);
- some arrive **twice**, and a few deliveries **crash** and roll back;
- then a rebalance redelivers **every** message to **4 consumers at once**.

Every message must take effect exactly once. You can create other tables in schema `inbox`;
the script runs twice, so make it rerunnable. (`inbox.published` is the broker's copy, for
reference only: `handle` must work from the message alone.)

## Hints
- Duplicates: keep the ids you've handled in a table with a primary key, and record the id in the same transaction as the effects. `INSERT ... ON CONFLICT DO NOTHING`, then `IF NOT FOUND THEN RETURN` (plpgsql sets `FOUND` when a row was inserted).
- Checking first with `IF EXISTS (SELECT ...)` is a race: 4 consumers can all see "not handled yet" at the same moment.
- Out of order: a status update should only win if its version is newer: `ON CONFLICT (order_id) DO UPDATE SET ... WHERE order_status.version < EXCLUDED.version`. The totals are additions (+1 when placed, −1 when cancelled or returned): they don't care about order, only about duplicates.
