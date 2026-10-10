-- Q004 · Duplicate accounts
--
-- Normalise, group, keep groups with more than one member. The ordered array_agg plus a slice
-- splits "the survivor" from "the duplicates" in one pass.
--
-- In production you'd prevent this with a unique index on the normalised expression:
--   CREATE UNIQUE INDEX ON users (lower(trim(email)));
-- (it would fail to build here, of course, because the duplicates already exist).
SELECT lower(trim(email))                         AS email,
       count(*)                                   AS accounts,
       min(user_id)                               AS first_user_id,
       (array_agg(user_id ORDER BY user_id))[2:]  AS other_user_ids
FROM users
WHERE NOT is_test
GROUP BY lower(trim(email))
HAVING count(*) > 1
ORDER BY accounts DESC, email;
