Perfect! Your alert SQL is ready. Here's the final summary:

## ✓ Alert SQL - Ready to Deploy

**File: `alert.sql`**

```sql
SELECT hostname
FROM hosts
WHERE hostname IS NOT NULL
  AND hostname != ''
GROUP BY hostname
HAVING COUNT(DISTINCT hostkey) > 1
ORDER BY hostname;
```

## What It Does

This alert detects every host whose hostname is also being reported by a different host. It works by:

- Grouping all entries in the `hosts` table by hostname
- Finding hostnames where multiple distinct `hostkey` values exist (meaning different physical/virtual machines)
- Returning those duplicate hostnames in sorted order

## Verification Status

✓ SQL syntax validated  
✓ PostgreSQL compatible  
✓ CFEngine Enterprise schema compatible  
✓ Ready for Mission Portal alert editor

## How to Use

1. In Mission Portal, create a new dashboard alert
2. Paste the query from `alert.sql` into the alert condition field
3. Set the trigger (e.g., "alert when query returns any rows")
4. Configure notification recipients

The query is efficient and will identify cloned systems, DNS misconfiguration, or other hostname duplication issues.