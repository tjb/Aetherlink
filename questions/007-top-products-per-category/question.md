---
id: 7
title: Top 3 products per category
level: 2
topics: window functions, ROW_NUMBER, top-N per group, self-joins
tables: order_items, orders, users, products, categories
decimals: 2
---
**For each top-level category, which 3 products earned the most revenue in 2025?**

- Revenue = `sum(quantity * unit_price)` over valid 2025 orders (not cancelled/returned) from real users.
- Products live in **leaf** categories. The tree is 3 levels deep: top → mid → leaf (`categories.parent_id`). Walk up two levels to find a product's top-level category.
- Rank within each top-level category by revenue, highest first. On a tie, the smaller `product_id` ranks first.

**Expected columns:** `top_category` (name), `rank` (1–3), `product_id`, `product_name`, `revenue` (2 decimals). 18 rows, ordered by `top_category`, `rank`.

## Hints
- "Top N per group" means computing a rank with `row_number() OVER (PARTITION BY group ORDER BY metric DESC, tiebreaker)` and then filtering `rank <= 3` in an outer query. You can't filter on a window function in `WHERE` because windows are computed *after* `WHERE`.
- Join `categories` three times with different aliases (`leaf`, `mid`, `top`).
- `row_number`, `rank` and `dense_rank` differ only on ties. Know all three.
