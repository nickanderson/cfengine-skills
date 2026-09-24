## Summary

Your alert SQL is ready! Here's what I've created:

**`alert.sql`** — The production-ready query:
```sql
SELECT h.hostkey
FROM hosts h
WHERE h.hostname IN (
    SELECT hostname
    FROM hosts
    GROUP BY hostname
    HAVING COUNT(DISTINCT hostkey) > 1
)
ORDER BY h.hostname, h.hostkey
```

**What it does:**
- Finds every host whose hostname is also reported by a different host
- Returns the `hostkey` of all affected hosts
- Orders results by hostname and hostkey for easy diagnosis

**To use in Mission Portal:**
1. Go to the Alert Editor
2. Paste the SQL from `alert.sql` into the Condition field
3. The alert will trigger for each host involved in a hostname conflict

The query has been validated for correct PostgreSQL syntax and logical soundness—it's ready to paste directly into your Mission Portal alert configuration.