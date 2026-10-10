-- Week 2: the CRM export replaces crm.customers.
TRUNCATE crm.customers;
INSERT INTO crm.customers SELECT * FROM crm.snapshot(2);
