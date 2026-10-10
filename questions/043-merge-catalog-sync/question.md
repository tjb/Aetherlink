---
id: 43
title: Sync a catalog with MERGE
level: 7
kind: pipeline
plan: setup, feed_1, answer, answer, feed_2, answer, answer, feed_3, answer, answer, check
topics: MERGE, upserts, change detection, soft deletes, IS DISTINCT FROM
tables: supplier.catalog_feed, supplier.catalog
---
A supplier sends us their **full catalogue** every day as a snapshot. Each feed replaces
`supplier.catalog_feed` (`sku`, `name`, `price`, `extracted_at`; every row of a feed has the same
`extracted_at`). We keep our own copy in **`supplier.catalog`**:

| column | meaning |
|---|---|
| `sku`, `name`, `price` | the latest values the supplier sent |
| `is_active` | is the SKU in the latest feed? |
| `first_seen_at` | `extracted_at` of the first feed that contained it |
| `updated_at` | `extracted_at` of the last feed that **changed** this row |
| `deactivated_at` | when it disappeared from the feed (NULL while active) |

Write the sync. For each feed:

- **new SKU**: insert it, active, with `first_seen_at = updated_at = extracted_at`;
- **SKU in the feed whose name or price changed, or that was inactive**: update the values, set it
  active, clear `deactivated_at`, set `updated_at`;
- **SKU in the feed and unchanged**: don't touch it. `updated_at` must keep its old value;
- **active SKU missing from the feed**: soft-delete it (`is_active = false`, set
  `deactivated_at` and `updated_at` to the feed's `extracted_at`), keeping name and price.

Use `extracted_at`, never `now()`. The checker lands three daily feeds and runs your sync **twice
after each one**, so a re-run must change nothing.

## Hints
- Postgres 15+ has `MERGE INTO target USING source ON ... WHEN MATCHED [AND ...] THEN UPDATE ... WHEN NOT MATCHED THEN INSERT ...`. Postgres 17 adds `WHEN NOT MATCHED BY SOURCE`: rows in the target that the feed doesn't mention. That's exactly the soft delete.
- "Changed" means `(c.name, c.price) IS DISTINCT FROM (f.name, f.price)`. A plain `<>` mishandles NULLs.
- The feed's timestamp, when the feed itself doesn't match the row: `(SELECT max(extracted_at) FROM supplier.catalog_feed)`.
- Without MERGE: `INSERT ... ON CONFLICT (sku) DO UPDATE ... WHERE <changed>`, plus a separate `UPDATE` for the deletions.
