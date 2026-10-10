---
id: 13
title: Revenue deciles
level: 2
topics: NTILE, windows over aggregates, cumulative share, Pareto
tables: orders, order_items, users
decimals: 1
---
Is our revenue concentrated in a few customers?

**Rank 2025's paying customers by their 2025 revenue and split them into 10 equal-sized deciles. Decile 1 is the top spenders. How much of the revenue does each decile bring?**

- Paying customer = a real user with at least one valid (not cancelled/returned) order in 2025. Revenue counts only those orders.
- Use `ntile(10)` ordered by revenue descending, ties broken by `user_id`.

**Expected columns:** `decile`, `customers`, `revenue` (2 decimals), `pct_of_revenue` (% of total, 1 decimal), `cumulative_pct` (running % including this decile, 1 decimal). 10 rows ordered by decile.

## Hints
- Three steps: revenue per customer → `ntile(10) OVER (ORDER BY revenue DESC, user_id)` → aggregate per decile.
- Window functions over the decile rows: `sum(revenue) OVER ()` for the total and `sum(revenue) OVER (ORDER BY decile)` for the running sum.
