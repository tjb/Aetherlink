---
id: 58
title: Concurrent transfers
level: 9
kind: pipeline
plan: setup, answer, answer, parallel:worker*4, check
topics: race conditions, check-then-act, lost updates, deadlocks, lock ordering, double-entry ledger
tables: wallet.accounts, wallet.ledger
---
Larkspur is adding store credit that customers can send to each other. Twelve wallets in
**`wallet.accounts`** start with 100.00 each.

**Write `wallet.transfer(p_from int, p_to int, p_amount numeric) RETURNS boolean`:**
- If `p_from` has at least `p_amount`, move the money and return **true**. Otherwise change
  nothing and return **false**. A wallet must **never** go below zero, not even for a moment.
- Record each successful transfer in the double-entry ledger **`wallet.ledger`**: two rows with
  the same `transfer_id` (from the sequence `wallet.transfer_ids`), `-p_amount` for `p_from` and
  `+p_amount` for `p_to`.

Then the checker starts the payments service: **4 sessions at once**, 800 transfers each, all
between the same 12 wallets, every transfer its own transaction. A transfer must never fail with
an error.

Afterwards no money may have appeared or vanished, and every balance must agree with the ledger
and with what `transfer` returned.

(`wallet.accounts.lowest` and `wallet.attempts` are the checker's; leave them alone.)

## Hints
- Reading the balance into a variable, checking it, then updating is a race: two transfers can both see 100.00 and both take 60.00. Put the condition in the write: `UPDATE ... SET balance = balance - p_amount WHERE account_id = p_from AND balance >= p_amount`, then `IF NOT FOUND`.
- If it fails with `deadlock detected`: one transfer locked A then B while another locked B then A. Lock both rows first, always in the same order: `PERFORM 1 FROM wallet.accounts WHERE account_id IN (p_from, p_to) ORDER BY account_id FOR UPDATE`.
- Everything inside one function call is one transaction: if anything fails, the balance changes and ledger rows disappear together.
