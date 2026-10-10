-- Q019 · Biggest referral trees
--
-- Seeding the recursion with *every* edge computes all trees in one go: each row is
-- (root, descendant, distance). The number of rows is the sum of all tree sizes, which is
-- fine for shallow trees but can explode for deep chains. In that case, start from the
-- candidate roots only.
--
-- Postgres has no index on users(referred_by) here, so each iteration hash-joins the whole
-- users table. Check EXPLAIN ANALYZE, then try CREATE INDEX ON users (referred_by).
WITH RECURSIVE tree AS (
  SELECT referred_by AS root_id, user_id, 1 AS depth
  FROM users
  WHERE referred_by IS NOT NULL
  UNION ALL
  SELECT t.root_id, u.user_id, t.depth + 1
  FROM tree t
  JOIN users u ON u.referred_by = t.user_id
)
SELECT t.root_id                            AS user_id,
       count(*) FILTER (WHERE t.depth = 1)  AS direct_referrals,
       count(*)                             AS total_referrals,
       max(t.depth)                         AS depth
FROM tree t
JOIN users r ON r.user_id = t.root_id
WHERE NOT r.is_test
GROUP BY t.root_id
ORDER BY total_referrals DESC, user_id
LIMIT 10;
