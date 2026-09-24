Perfect! Both tests pass. The SQL correctly identifies hosts with duplicate hostnames:

- **Direct query**: Returns 2 rows (2 hosts have duplicate hostnames)
- **Wrapped query**: Shows both hosts are named "hub.example.com" but have different hostkeys

Here's your ready-to-paste alert condition:

```sql
SELECT DISTINCT hostkey
FROM hosts
WHERE hostname IN (
  SELECT hostname
  FROM hosts
  WHERE hostname IS NOT NULL
  GROUP BY hostname
  HAVING count(DISTINCT hostkey) > 1
)
AND hostname IS NOT NULL
```

**How it works:**
- The subquery finds all hostnames reported by more than one distinct host
- The outer query returns the `hostkey` of every host with a duplicate hostname
- The `DISTINCT` ensures one row per failing host
- Null hostnames are filtered out to avoid spurious matches

It's in `alert.sql` and verified against your 3.27.1 hub.