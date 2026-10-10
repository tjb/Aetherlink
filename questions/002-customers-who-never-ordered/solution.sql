-- Q002 · Customers who never ordered
--
-- NOT EXISTS is the clearest way to say "has no matching row". Postgres plans it as a hash
-- anti-join, so it's one pass over each table no matter how many orders a user has.
--
-- Equivalent: LEFT JOIN orders o ... WHERE o.user_id IS NULL. But the join version needs
-- care when you also aggregate, because users WITH orders fan out to one row per order.
WITH flagged AS (
  SELECT u.country,
         NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.user_id) AS never_ordered
  FROM users u
  WHERE NOT u.is_test
)
SELECT country,
       count(*)                                                          AS users,
       count(*) FILTER (WHERE never_ordered)                             AS never_ordered,
       round(100.0 * count(*) FILTER (WHERE never_ordered) / count(*), 1) AS pct_never_ordered
FROM flagged
GROUP BY country
ORDER BY pct_never_ordered DESC, country;
