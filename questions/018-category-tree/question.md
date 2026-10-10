---
id: 18
title: Category tree rollup
level: 3
topics: recursive CTEs, hierarchies, closure tables
tables: categories, products, order_items, orders, users
decimals: 2
---
**For every category, show its full path from the top of the tree, its depth, and the 2025 revenue of everything in it, including all descendant categories.**

- Path format: names joined with `' > '`, e.g. `Electronics > Audio > Headphones`. Note that two different categories are called `Shoes`.
- `depth` is 1 for top-level categories, 2 for their children, and so on.
- Revenue: valid 2025 orders (not cancelled/returned) from real users. Products belong to leaf categories. A parent's revenue is the sum over its whole subtree. Categories with no revenue show `0`.

**Expected columns:** `category_id`, `path`, `depth`, `revenue` (2 decimals). One row per category (82), ordered by `path`.

## Hints
- `WITH RECURSIVE`: an anchor query (the roots, `parent_id IS NULL`) `UNION ALL` a recursive query that joins `categories` to the rows found so far.
- To roll revenue up, build a *closure table*: every `(ancestor_id, descendant_id)` pair, including each category with itself. That's another recursive CTE. Then join revenue on the descendant and group by the ancestor.
- You can define several recursive CTEs in one `WITH RECURSIVE`.
- The tree here is only 3 levels deep, so you *could* hard-code three self-joins. Don't: the recursive version works at any depth.
