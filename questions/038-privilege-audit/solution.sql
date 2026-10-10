-- Q038 · Privilege audit
--
-- has_table_privilege(role, table, privilege) answers "could this role do X right now, without
-- SET ROLE?" It follows inherited memberships (oncall -> etl -> app_rw) and ignores
-- non-inherited ones (intern is a member of app_rw WITH INHERIT FALSE, so it gets nothing
-- until it runs SET ROLE app_rw).
--
-- What the catalog-only approaches miss:
--   * information_schema.table_privileges shows direct grants only: no oncall rows for events.
--   * A recursive walk over pg_auth_members gets inheritance right only if you also respect
--     the inherit_option column (Postgres 16+); otherwise intern looks dangerous when it isn't.
--   * Neither shows the implicit powers: table OWNERS and superusers can do everything,
--     whatever the grants say. Your migrations probably run as the owner...
--
-- Least privilege in practice: app roles get SELECT/INSERT/UPDATE/DELETE on what they need,
-- TRUNCATE and DDL stay with a separate migration/owner role, humans get read-only by default
-- and SET ROLE (NOINHERIT) for break-glass access.
SELECT r.role,
       t.table_name,
       has_table_privilege(r.role, format('public.%I', t.table_name), 'DELETE')   AS can_delete,
       has_table_privilege(r.role, format('public.%I', t.table_name), 'TRUNCATE') AS can_truncate
FROM (VALUES ('analyst'), ('app_rw'), ('etl'), ('oncall'), ('intern')) AS r(role)
CROSS JOIN (VALUES ('users'), ('categories'), ('products'), ('product_prices'), ('orders'),
                   ('order_items'), ('events'), ('reviews'), ('subscriptions')) AS t(table_name)
WHERE has_table_privilege(r.role, format('public.%I', t.table_name), 'DELETE')
   OR has_table_privilege(r.role, format('public.%I', t.table_name), 'TRUNCATE')
ORDER BY r.role, t.table_name;
