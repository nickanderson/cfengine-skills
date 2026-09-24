Excellent! Both tests pass. The alert condition is working correctly:

**Test results:**
- ✅ Direct query: Returns 4 failing hosts (2 with hostname "host004.example.com", 2 with "hub.example.com")
- ✅ Wrapped query: Correctly joins with the hosts table and displays host details in the alert view

The SQL detects duplicate hostnames by finding every host whose hostname is also reported by a different hostkey. Here's the final SQL for the alert editor:

```sql
SELECT DISTINCT h1.hostkey, h1.hostname
FROM hosts h1
WHERE EXISTS (
  SELECT 1 FROM hosts h2
  WHERE h1.hostname = h2.hostname
  AND h1.hostkey != h2.hostkey
)
```

**How it works:**
- Returns one row per failing host (uses `DISTINCT h1.hostkey`)
- Includes the required `hostkey` column for Mission Portal
- Uses the current-state `hosts` view (not history tables)
- No trailing semicolon or comments (safe for Mission Portal's wrapping)

The file is ready at `/tmp/cfeval-mp-02-alert-sql-with-skill.IhmoOqam/work/alert.sql` for you to paste into Dashboard → New Alert → Custom SQL condition.