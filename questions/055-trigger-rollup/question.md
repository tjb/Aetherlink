---
id: 55
title: A rollup that keeps itself up to date
level: 9
kind: pipeline
plan: setup, answer, answer, parallel:writers*4, changes, check
topics: triggers, transition tables, lost updates, atomic increments, ON CONFLICT, backfills
tables: rollup.order_items, rollup.product_sales
---
The product page shows "units sold", and summing `order_items` on every page view is too slow.
Keep a running total instead: **`rollup.product_sales`** (`product_id` primary key, `units`,
`revenue`) must always equal, for each product, `sum(quantity)` and `sum(quantity * unit_price)`
over **`rollup.order_items`**.

Write a script that sets it up with **triggers** on `rollup.order_items`:
- **Backfill** the lines already in the table.
- Handle **inserts, updates and deletes**: quantity changes, price corrections, and lines moved
  to a different product.
- The script must be safe to **run twice** (the checker does).

Then the checker lets traffic in: **4 sessions at once** sell the same dozen popular products, one
line per transaction, editing and cancelling some as they go. After that, back office fixes and a
20,000-line bulk import. Every total must still be exact.

A product with no lines may have no row, or a row of zeros.

## Hints
- An update is "take away the old line, add the new one": `OLD` and `NEW` in a row-level trigger (`AFTER INSERT OR UPDATE OR DELETE ... FOR EACH ROW`), with `TG_OP` telling you which happened.
- Don't read the total into a variable and write back `total + n`: two sessions read the same value and one sale disappears. Let one statement do it: `INSERT ... ON CONFLICT (product_id) DO UPDATE SET units = product_sales.units + EXCLUDED.units`.
- To backfill safely and repeatably, recompute everything inside one transaction: delete the totals and insert `GROUP BY product_id` from the lines. `LOCK TABLE` first, so nobody writes between creating the triggers and taking the totals.
