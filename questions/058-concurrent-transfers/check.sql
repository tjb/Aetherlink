WITH per_account AS (
  SELECT a.account_id, a.balance, a.lowest,
         coalesce((SELECT sum(amount) FROM wallet.ledger l WHERE l.account_id = a.account_id), 0) AS ledger_net,
         coalesce((SELECT sum(CASE WHEN t.to_account = a.account_id THEN t.amount ELSE -t.amount END)
                   FROM wallet.attempts t
                   WHERE t.ok AND a.account_id IN (t.from_account, t.to_account)), 0) AS told_net
  FROM wallet.accounts a
), transfers AS (
  SELECT transfer_id, count(*) AS entries, sum(amount) AS total,
         count(*) FILTER (WHERE amount < 0) AS outs
  FROM wallet.ledger GROUP BY transfer_id
)
SELECT 'no money was created or destroyed' AS check,
       sum(balance) = 1200.00 AS ok,
       format('the wallets hold %s in total, and started with 1200.00', sum(balance)) AS detail
FROM wallet.accounts
UNION ALL
SELECT 'no wallet ever went below zero',
       min(lowest) >= 0,
       format('lowest balance ever seen: %s', min(lowest))
FROM wallet.accounts
UNION ALL
SELECT 'every transfer returned true or false',
       count(*) FILTER (WHERE ok IS NULL) = 0 AND count(*) = 3200,
       format('%s attempts, %s succeeded, %s declined, %s returned NULL', count(*),
              count(*) FILTER (WHERE ok), count(*) FILTER (WHERE NOT ok), count(*) FILTER (WHERE ok IS NULL))
FROM wallet.attempts
UNION ALL
SELECT 'every transfer in the ledger is two entries that cancel out',
       count(*) > 0 AND count(*) FILTER (WHERE entries <> 2 OR total <> 0 OR outs <> 1) = 0,
       format('%s transfers, %s unbalanced', count(*), count(*) FILTER (WHERE entries <> 2 OR total <> 0 OR outs <> 1))
FROM transfers
UNION ALL
SELECT 'the ledger has one transfer per successful attempt',
       (SELECT count(*) FROM transfers) = (SELECT count(*) FROM wallet.attempts WHERE ok),
       format('%s transfers in the ledger, %s attempts returned true',
              (SELECT count(*) FROM transfers), (SELECT count(*) FROM wallet.attempts WHERE ok))
UNION ALL
SELECT 'every balance = 100.00 + its ledger entries = 100.00 + the transfers that returned true',
       count(*) FILTER (WHERE balance <> 100 + ledger_net OR balance <> 100 + told_net) = 0,
       format('%s of 12 wallets disagree', count(*) FILTER (WHERE balance <> 100 + ledger_net OR balance <> 100 + told_net))
       || coalesce(', e.g. ' || min(format('wallet %s holds %s, its ledger says %s, the transfers say %s',
                                           account_id, balance, 100 + ledger_net, 100 + told_net))
                   FILTER (WHERE balance <> 100 + ledger_net OR balance <> 100 + told_net), '')
FROM per_account;
