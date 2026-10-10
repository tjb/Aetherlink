---
id: 11
title: MoM and YoY growth
level: 2
topics: LAG, growth rates, filter after window
tables: orders, order_items, users
decimals: 1
---
**Monthly revenue for every month of 2024 and 2025, with month-over-month (MoM) and year-over-year (YoY) growth.**

- Revenue = valid orders (not cancelled/returned) from real users.
- Growth % = `100 * (this / previous - 1)`. MoM compares with the previous month, YoY with the same month a year earlier.
- January 2024's MoM compares with December 2023. All of 2024's YoY compare with 2023. **No NULLs expected.**

**Expected columns:** `month` (date), `revenue`, `mom_growth_pct`, `yoy_growth_pct` (1 decimal). 24 rows ordered by month.

## Hints
- `lag(revenue) OVER (ORDER BY month)` is last month. `lag(revenue, 12) OVER (ORDER BY month)` is 12 *rows* back. That's 12 months back only if no month is missing.
- As in Q009, compute the window over all months, then filter to 2024–2025 in an outer query.
