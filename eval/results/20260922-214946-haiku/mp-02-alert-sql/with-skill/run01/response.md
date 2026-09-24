Excellent! Both tests pass. The SQL detects 2 hosts sharing the hostname `hub.example.com`.

**alert.sql** is ready:

```sql
SELECT DISTINCT h.hostkey
FROM hosts h
WHERE h.hostname IN (
  SELECT hostname FROM hosts GROUP BY hostname HAVING count(*) > 1
)
```

This condition:
- ✅ Returns `hostkey` (required by Mission Portal)
- ✅ Uses `SELECT DISTINCT` to ensure one row per failing host
- ✅ Queries the current-state `hosts` view (not history)
- ✅ Tested both as a direct status query (rowCount: 2) and wrapped for the host list view (2 rows with hostname and hostkey)

The alert will trigger whenever a hostname is reported by multiple hosts with different hostkeys. Paste it directly into the Mission Portal alert editor under Dashboard → Add Alert → Custom SQL.