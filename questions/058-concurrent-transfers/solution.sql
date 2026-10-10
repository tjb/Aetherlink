-- Q058 · Concurrent transfers
--
-- Three bugs that only show up under concurrency:
--
--  * Check-then-act. "SELECT balance; IF balance >= amount THEN UPDATE ..." Two transfers out
--    of the same wallet both read 100.00, both pass the check, and the wallet ends at -20.00.
--    Make the check part of the write: UPDATE ... WHERE balance >= amount. In READ COMMITTED,
--    if another transaction changed the row first, the UPDATE waits for it, then re-checks the
--    WHERE clause against the new balance.
--
--  * Lost updates. "SET balance = v_balance - amount" with a value read earlier overwrites a
--    concurrent change. Write "balance = balance - amount" and let the row lock serialize it.
--
--  * Deadlocks. Transfer A->B locks A then B; at the same moment B->A locks B then A. Each
--    waits for the other forever, until Postgres notices (after deadlock_timeout, 1 s) and
--    kills one of them. The fix is a global lock order: lock both rows up front, lowest id
--    first, so two transfers touching the same wallets always queue in the same order.
--
-- The alternative is SERIALIZABLE isolation: write the naive code and Postgres aborts any
-- transaction that would produce a result impossible in some serial order. It's simpler to
-- reason about, but you must retry on serialization failures (SQLSTATE 40001), and that retry
-- loop has to live outside the transaction, in the application.
--
-- Double-entry bookkeeping: the ledger is the truth (append-only, two entries that sum to zero
-- per transfer) and the balance is a cache of it, updated in the same transaction.
CREATE OR REPLACE FUNCTION wallet.transfer(p_from int, p_to int, p_amount numeric) RETURNS boolean
LANGUAGE plpgsql AS $$
DECLARE
  t bigint;
BEGIN
  IF p_amount <= 0 OR p_from = p_to THEN
    RAISE EXCEPTION 'invalid transfer: % from % to %', p_amount, p_from, p_to;
  END IF;

  -- lock both wallets in a fixed order before touching either
  PERFORM 1 FROM wallet.accounts
  WHERE account_id IN (p_from, p_to)
  ORDER BY account_id
  FOR UPDATE;

  UPDATE wallet.accounts SET balance = balance - p_amount
  WHERE account_id = p_from AND balance >= p_amount;
  IF NOT FOUND THEN
    RETURN false;  -- not enough money (nothing was changed)
  END IF;
  UPDATE wallet.accounts SET balance = balance + p_amount WHERE account_id = p_to;

  t := nextval('wallet.transfer_ids');
  INSERT INTO wallet.ledger (transfer_id, account_id, amount)
  VALUES (t, p_from, -p_amount), (t, p_to, p_amount);
  RETURN true;
END $$;
