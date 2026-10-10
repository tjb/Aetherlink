WITH snaps AS (
  SELECT k, s.* FROM generate_series(1, 3) AS k CROSS JOIN LATERAL crm.snapshot(k) AS s
), changes AS (
  SELECT *, (email, country, plan) IS DISTINCT FROM
            (lag(email) OVER w, lag(country) OVER w, lag(plan) OVER w) AS changed
  FROM snaps
  WINDOW w AS (PARTITION BY user_id ORDER BY k)
), expected AS (
  SELECT user_id, email, country, plan, snapshot_at AS valid_from,
         lead(snapshot_at) OVER (PARTITION BY user_id ORDER BY k) AS valid_to
  FROM changes
  WHERE changed
), exp AS (
  SELECT user_id, email, country, plan, valid_from, valid_to, valid_to IS NULL AS is_current FROM expected
), got AS (
  SELECT user_id, email, country, plan, valid_from, valid_to, is_current FROM crm.dim_customer_history
)
SELECT 'the history has exactly the expected versions' AS check,
       NOT EXISTS (SELECT * FROM exp EXCEPT ALL SELECT * FROM got)
         AND NOT EXISTS (SELECT * FROM got EXCEPT ALL SELECT * FROM exp) AS ok,
       format('%s rows, expected %s; %s missing, %s unexpected',
              (SELECT count(*) FROM got), (SELECT count(*) FROM exp),
              (SELECT count(*) FROM (SELECT * FROM exp EXCEPT ALL SELECT * FROM got) a),
              (SELECT count(*) FROM (SELECT * FROM got EXCEPT ALL SELECT * FROM exp) b)) AS detail
UNION ALL
SELECT 'exactly one current row per customer',
       NOT EXISTS (SELECT user_id FROM crm.dim_customer_history GROUP BY user_id
                   HAVING count(*) FILTER (WHERE is_current) <> 1),
       format('%s customers with zero or several current rows',
              (SELECT count(*) FROM (SELECT user_id FROM crm.dim_customer_history GROUP BY user_id
                                     HAVING count(*) FILTER (WHERE is_current) <> 1) x))
UNION ALL
SELECT 'is_current is true exactly when valid_to is NULL',
       NOT EXISTS (SELECT 1 FROM crm.dim_customer_history WHERE is_current <> (valid_to IS NULL)), ''
UNION ALL
SELECT 'versions of a customer never overlap',
       NOT EXISTS (SELECT 1 FROM crm.dim_customer_history a
                   JOIN crm.dim_customer_history b
                     ON a.user_id = b.user_id AND a.customer_sk < b.customer_sk
                    AND a.valid_from < coalesce(b.valid_to, 'infinity')
                    AND b.valid_from < coalesce(a.valid_to, 'infinity')), ''
UNION ALL
SELECT 'surrogate keys are filled automatically',
       NOT EXISTS (SELECT 1 FROM crm.dim_customer_history WHERE customer_sk IS NULL)
         AND (SELECT count(DISTINCT customer_sk) = count(*) FROM crm.dim_customer_history), ''
