Perfect! The SQL has been validated against your hub. The alert condition detected **2 hosts sharing the same hostname** (`hub.example.com`), and both test forms passed successfully.

Here's your final alert SQL, ready to paste into the Mission Portal alert editor:

```sql
SELECT h.hostkey
FROM hosts h
WHERE h.hostname IN (
  SELECT hostname
  FROM hosts
  WHERE hostname IS NOT NULL
  GROUP BY hostname
  HAVING COUNT(DISTINCT hostkey) > 1
)
```

The query works by:
1. Finding all hostnames that appear more than once (grouped by hostname, with count of distinct hostkeys > 1)
2. Returning the `hostkey` of each host with a duplicate hostname
3. Filtering out NULL hostnames to avoid spurious matches

The condition has been tested in both:
- **Raw form** (the condition itself) — returned 2 rows
- **Wrapped form** (as Mission Portal executes it in the UI) — returned 2 rows with hostname and hostkey

The file `alert.sql` is ready in your working directory.