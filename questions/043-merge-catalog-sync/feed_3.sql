-- Day 3: the supplier's feed replaces supplier.catalog_feed.
TRUNCATE supplier.catalog_feed;
INSERT INTO supplier.catalog_feed SELECT * FROM supplier.snapshot(3);
