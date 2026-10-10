WITH expected AS (
  SELECT o.order_id,
         date_trunc('minute', o.created_at) AS ordered_at,
         lower(trim(u.email)) AS customer_email,
         CASE WHEN abs(hashint8extended(o.order_id, 401)) % 100 < 5 THEN NULL ELSE u.country END AS country,
         t.units::int AS units,
         round(t.total, 2) AS total,
         o.status,
         CASE abs(hashint8extended(o.order_id, 403)) % 20
           WHEN 0 THEN 'Gift wrap, please'
           WHEN 1 THEN 'Leave at the "back" door'
           WHEN 2 THEN 'Call before delivery; gate code 1234'
           WHEN 3 THEN 'Fragile!'
           ELSE NULL END AS notes
  FROM orders o
  JOIN users u ON u.user_id = o.user_id
  JOIN (SELECT order_id, sum(quantity) AS units, sum(quantity * unit_price) AS total
        FROM order_items GROUP BY order_id) t ON t.order_id = o.order_id
  WHERE o.created_at >= '2025-12-01' AND o.created_at < '2026-01-01'
    AND o.ship_country IN ('DE', 'FR', 'NL', 'ES')
), j AS (
  SELECT e.*, g.order_id AS g_id, g.ordered_at AS g_ordered_at, g.customer_email AS g_email,
         g.country AS g_country, g.units AS g_units, g.total AS g_total, g.status AS g_status, g.notes AS g_notes
  FROM expected e
  LEFT JOIN partner.orders g ON g.order_id = e.order_id
)
SELECT 'every order loaded, exactly once' AS check,
       (SELECT count(*) FROM partner.orders) = (SELECT count(*) FROM expected)
         AND NOT EXISTS (SELECT order_id FROM partner.orders EXCEPT SELECT order_id FROM expected) AS ok,
       format('%s rows loaded, %s orders in the file', (SELECT count(*) FROM partner.orders),
              (SELECT count(*) FROM expected)) AS detail
UNION ALL
SELECT 'ordered_at is the right instant (Berlin time, day/month/year)',
       count(*) FILTER (WHERE g_ordered_at IS DISTINCT FROM ordered_at) = 0,
       coalesce(min(format('order %s: expected %s, got %s', order_id, ordered_at, g_ordered_at))
                FILTER (WHERE g_id IS NOT NULL AND g_ordered_at IS DISTINCT FROM ordered_at), '')
FROM j
UNION ALL
SELECT 'emails are lower case and trimmed',
       count(*) FILTER (WHERE g_email IS DISTINCT FROM customer_email) = 0,
       coalesce(min(format('order %s: %L', order_id, g_email))
                FILTER (WHERE g_id IS NOT NULL AND g_email IS DISTINCT FROM customer_email), '')
FROM j
UNION ALL
SELECT 'totals and units are right',
       count(*) FILTER (WHERE (g_total, g_units) IS DISTINCT FROM (total, units)) = 0,
       coalesce(min(format('order %s: expected %s, got %s', order_id, total, g_total))
                FILTER (WHERE g_id IS NOT NULL AND (g_total, g_units) IS DISTINCT FROM (total, units)), '')
FROM j
UNION ALL
SELECT 'status is lower case and trimmed',
       count(*) FILTER (WHERE g_status IS DISTINCT FROM status) = 0,
       coalesce(min(format('order %s: %L', order_id, g_status))
                FILTER (WHERE g_id IS NOT NULL AND g_status IS DISTINCT FROM status), '')
FROM j
UNION ALL
SELECT 'empty fields are NULL (country, notes) and notes are intact',
       count(*) FILTER (WHERE (g_country, g_notes) IS DISTINCT FROM (country, notes)) = 0,
       coalesce(min(format('order %s: country=%L notes=%L', order_id, g_country, g_notes))
                FILTER (WHERE g_id IS NOT NULL AND (g_country, g_notes) IS DISTINCT FROM (country, notes)), '')
FROM j
