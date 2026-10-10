-- Lab for Q058: store-credit wallets, a double-entry ledger, and the record of every attempt.
DROP SCHEMA IF EXISTS wallet CASCADE;
CREATE SCHEMA wallet;

CREATE TABLE wallet.accounts (
  account_id int PRIMARY KEY,
  user_id    bigint NOT NULL,
  balance    numeric(12,2) NOT NULL,
  lowest     numeric(12,2) NOT NULL  -- the lowest balance it has ever had (kept by a trigger)
);
INSERT INTO wallet.accounts
SELECT row_number() OVER (ORDER BY user_id), user_id, 100.00, 100.00
FROM (SELECT user_id FROM users WHERE NOT is_test ORDER BY user_id LIMIT 12) u;

-- The checker's own bookkeeping: don't touch.
CREATE FUNCTION wallet.track_lowest() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.lowest := least(OLD.lowest, NEW.balance);
  RETURN NEW;
END $$;
CREATE TRIGGER accounts_track_lowest BEFORE UPDATE ON wallet.accounts
FOR EACH ROW EXECUTE FUNCTION wallet.track_lowest();

CREATE SEQUENCE wallet.transfer_ids;
CREATE TABLE wallet.ledger (
  entry_id    bigserial PRIMARY KEY,
  transfer_id bigint NOT NULL,
  account_id  int NOT NULL REFERENCES wallet.accounts,
  amount      numeric(12,2) NOT NULL,  -- negative: money leaving the account
  created_at  timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE wallet.attempts (
  worker       int NOT NULL,
  n            int NOT NULL,
  from_account int NOT NULL,
  to_account   int NOT NULL,
  amount       numeric(12,2) NOT NULL,
  ok           boolean,
  PRIMARY KEY (worker, n)
);
