# The Larkspur dataset

Larkspur is a fictional online marketplace: three years of customers, a product catalogue with
price history, orders, a clickstream, reviews and a paid membership. Everything is generated
inside Postgres by [`db/generate.sql`](../db/generate.sql). It's deterministic, so the same
scale always produces identical data.

```
categories ─┬─< categories (parent_id)          users ─┬─< users (referred_by)
            └─< products ─┬─< product_prices           ├─< orders ─┬─< order_items >── products
                          ├─< order_items              │           └─< reviews
                          ├─< reviews                  ├─< subscriptions
                          └─< events (product_id)      └─< events (user_id, nullable)
```

## Conventions

- **Everything is UTC.** Timestamps are `timestamptz` and the server's time zone is UTC, so
  `created_at::date` is the UTC date. Users' own zones are in `users.timezone`.
- **The data covers 2023-01-01 to 2026-01-01 (exclusive).** "2025" means
  `ts >= '2025-01-01' AND ts < '2026-01-01'`.
- **Real users** are `users.is_test = false`. QA bots buy a lot and distort metrics.
- **Valid orders** have `status NOT IN ('cancelled', 'returned')`.
- **Revenue** is `sum(order_items.quantity * order_items.unit_price)` over valid orders from real users,
  unless a question says otherwise.

## Size

| scale | users | events | orders | disk | generation* |
|------:|------:|-------:|-------:|-----:|-----------:|
| 0.05 | 5k | 0.3M | 4.7k | 50 MB | 4 s |
| 1 (default) | 100k | 5.8M | 92k | 0.8 GB | 45 s |
| 5 | 500k | 29M | 457k | 3.8 GB | 3.6 min |
| 10 | 1M | 58M | 0.9M | ~7.5 GB | ~8 min |

\* on a 4-core cloud VM; a recent laptop is usually faster. Products grow with √scale
(5,000 at scale 1).

## Tables

### `users`
| column | type | notes |
|---|---|---|
| `user_id` | bigint PK | ids follow sign-up order |
| `email` | text | **not unique**: some people signed up twice with different casing/whitespace |
| `full_name` | text | |
| `country` | char(2) | US, GB, DE, FR, CA, IN, BR, AU, JP, MX, NL, ES |
| `timezone` | text | IANA zone, e.g. `America/Chicago` |
| `signup_at` | timestamptz | sign-ups accelerate over time |
| `referral_source` | text | organic, ads, social, referral, email, or **NULL** (unknown) |
| `referred_by` | bigint → users | who invited them (only for `referral`); forms trees |
| `birth_date` | date | sometimes NULL |
| `is_test` | boolean | QA bot accounts (`@larkspur.test`) |

### `categories`
A fixed 3-level tree: 6 top-level → 19 mid-level → 57 leaf categories (`parent_id` NULL at the top).
Names aren't unique (there's a *Men > Shoes* and a *Women > Shoes*).

### `products`
| column | type | notes |
|---|---|---|
| `product_id` | int PK | |
| `category_id` | int → categories | always a **leaf** category |
| `name`, `brand` | text | |
| `price` | numeric | the **current** list price. For history use `product_prices` |
| `created_at` | timestamptz | all products existed before 2023 |

Popularity has a long tail: a few products sell enormously, most rarely.

### `product_prices` (price history, "SCD type 2")
| column | type | notes |
|---|---|---|
| `product_id` | int → products | PK is `(product_id, valid_from)` |
| `valid_from` | timestamptz | inclusive |
| `valid_to` | timestamptz | exclusive; **NULL = current price** |
| `price` | numeric | |

### `orders`
| column | type | notes |
|---|---|---|
| `order_id` | bigint PK | increases with `created_at` |
| `user_id` | bigint → users | indexed |
| `created_at` | timestamptz | strong November/December seasonality, Black Friday spike |
| `status` | text | `pending`, `shipped`, `delivered`, `returned`, `cancelled` |
| `device` | text | `mobile`, `desktop`, `tablet` (desktop converts best) |
| `ship_country` | char(2) | |
| `carrier` | text | UPS, FedEx, USPS (US) / DHL (international); NULL until shipped |
| `shipped_at`, `delivered_at` | timestamptz | NULL until it happens |

### `order_items`
| column | type | notes |
|---|---|---|
| `order_id` | bigint → orders | PK is `(order_id, line_no)` |
| `line_no` | int | |
| `product_id` | int → products | some products are usually bought together |
| `quantity` | int | |
| `unit_price` | numeric | the price actually charged (the price in effect when ordered) |

### `events`: the big one (~6M rows per unit of scale)
| column | type | notes |
|---|---|---|
| `event_id` | bigint PK | increases with time; rows are physically stored in time order |
| `occurred_at` | timestamptz | millisecond precision |
| `user_id` | bigint | **NULL when the visitor wasn't logged in** |
| `device` | text | |
| `event_type` | text | `page_view`, `search`, `product_view`, `add_to_cart`, `checkout_started`, `purchase` |
| `product_id` | int | for `product_view` and `add_to_cart` |
| `properties` | jsonb | depends on the type: `{"path", "referrer"}`, `{"query"}`, `{"source"}`, `{"quantity"}`, `{"items"}`, `{"order_id"}` |

There's **no session id**: rebuilding sessions is a question. A `purchase` event's
`properties->>'order_id'` points to `orders`.

### `reviews`
`review_id`, `product_id`, `user_id`, `order_id`, `rating` (1–5), `created_at`. Written by customers
after delivery. Returned items and slow deliveries get worse ratings.

### `subscriptions` (Larkspur Plus membership)
| column | type | notes |
|---|---|---|
| `subscription_id` | bigint PK | |
| `user_id` | bigint → users | people churn and come back, so a user can have several rows |
| `plan` | text | `monthly` or `annual` |
| `monthly_price` | numeric | normalised: annual plans show price / 12 |
| `started_at` | timestamptz | inclusive |
| `ended_at` | timestamptz | exclusive; **NULL = still active** |

## Indexes

Deliberately minimal: primary keys, foreign keys (constraints only) and `orders(user_id)`.
Choosing the right indexes is part of the curriculum. `./dojo reset` (or *Reset objects I
created* in the TUI) drops everything you add and returns to this baseline.

## Labs (Level 6)

Lab questions create their own objects in the **`lab`** schema (and a few roles: `app_migrator`,
`analyst`, `app_rw`, `etl`, `oncall`, `intern`) the first time you open them. Rebuild one with
*Reset this lab* (`./dojo lab-reset N`). Regenerating the dataset drops the `lab` schema too.

## Realistic dirt

Real data is messy, and so is this. Some questions depend on spotting it. If you'd rather find
the problems yourself, stop reading here.

<details>
<summary>Spoilers: the known data quality issues</summary>

- Duplicate accounts: about 1% of users re-registered with an email differing only in case or
  trailing whitespace.
- NULL `referral_source` for about 20% of users; `referred_by` is NULL for almost everyone.
- QA bot accounts (`is_test`) with very high order volume.
- About 0.4% of events were delivered twice (identical except `event_id`).
- About 3% of orders have no `purchase` event (ad blockers).
- About 0.2% of delivered orders have `delivered_at` *before* `shipped_at` (a faulty scanner).
- About 1% of subscribers got a second, overlapping subscription from a billing bug.
- Logged-out activity (`events.user_id IS NULL`) can't be attributed to anyone.

</details>
