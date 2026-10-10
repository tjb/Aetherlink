---
id: 19
title: Biggest referral trees
level: 3
topics: recursive CTEs, graph traversal, self-referencing tables
tables: users
---
Users can invite others (`users.referred_by` is the inviter's `user_id`). A user's **referral tree** is everyone they invited directly, plus everyone *those* people invited, and so on down.

**Which 10 real users have the largest referral trees?**

**Expected columns:**
- `user_id`
- `direct_referrals`: people they invited themselves
- `total_referrals`: everyone in their tree at any depth (not counting themselves)
- `depth`: the longest invitation chain below them (1 = only direct invites)

10 rows ordered by `total_referrals` descending, then `user_id`.

## Hints
- Start the recursion from every invitation edge at once: anchor = `SELECT referred_by AS root_id, user_id, 1 AS depth FROM users WHERE referred_by IS NOT NULL`.
- The recursive step finds people invited by the users found so far, keeping `root_id` and adding 1 to `depth`.
- Then a plain `GROUP BY root_id`, with `count(*) FILTER (WHERE depth = 1)` for the direct invites.
