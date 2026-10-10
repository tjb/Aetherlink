---
id: 38
title: Privilege audit
level: 6
topics: roles, GRANT, role membership, INHERIT, has_table_privilege
tables: pg_roles, pg_auth_members, information_schema.table_privileges
---
After the TRUNCATE incident, security wants an audit: **who can destroy data in the dataset tables?**

The lab creates five roles with direct grants *and* memberships in each other:
`analyst`, `app_rw`, `etl`, `oncall` and `intern`. Look around: `\du` in psql, `pg_auth_members`,
`\dp orders`.

**For each of those five roles and each of the nine dataset tables** (`users`, `categories`,
`products`, `product_prices`, `orders`, `order_items`, `events`, `reviews`, `subscriptions`),
**can the role DELETE from it, and can it TRUNCATE it?** Count what the role can do without
running `SET ROLE` first: its own grants plus everything it inherits. Return only the
role/table pairs where at least one answer is yes.

**Expected columns:** `role`, `table_name`, `can_delete`, `can_truncate` (booleans). Ordered by
`role`, `table_name`.

## Hints
- `information_schema.table_privileges` lists grants made *directly* to a role. Privileges a role has through membership in another role don't appear there.
- Role memberships can be inherited or not (`INHERIT` / `NOINHERIT`). A member with NOINHERIT must `SET ROLE` to use the other role's privileges.
- Postgres can answer the question for you: `has_table_privilege(role, table, privilege)` follows inherited memberships correctly.
