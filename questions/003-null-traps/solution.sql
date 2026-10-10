-- Q003 · NULL traps
--
-- Trap 1: WHERE referral_source <> 'ads' silently drops every NULL row, because
--         NULL <> 'ads' evaluates to NULL (unknown), not TRUE.
--         IS DISTINCT FROM treats NULL as an ordinary comparable value.
--         (Also fine: referral_source <> 'ads' OR referral_source IS NULL, or coalesce.)
--
-- Trap 2: WHERE user_id NOT IN (SELECT referred_by FROM users) returns ZERO rows, because the
--         subquery contains NULLs: "x NOT IN (..., NULL)" is never TRUE. NOT EXISTS has no such
--         problem, which is why many style guides ban NOT IN with subqueries entirely.
SELECT
  (SELECT count(*)
   FROM users
   WHERE NOT is_test
     AND referral_source IS DISTINCT FROM 'ads')                    AS not_from_ads,
  (SELECT count(*)
   FROM users u
   WHERE NOT u.is_test
     AND NOT EXISTS (SELECT 1 FROM users r WHERE r.referred_by = u.user_id)) AS never_referred_anyone;
