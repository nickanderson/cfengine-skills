Perfect! I've created and validated the SQL alert query for detecting hostname conflicts in your CFEngine Mission Portal. Here's the final solution:

## Alert SQL Query

The SQL query in `alert.sql` is ready to paste into the Mission Portal alert editor:

```sql
SELECT DISTINCT h.hostname
FROM hosts h
WHERE h.hostname IN (
    SELECT hostname
    FROM hosts
    GROUP BY hostname
    HAVING COUNT(DISTINCT hostkey) > 1
)
ORDER BY h.hostname;
```

## What This Query Does

This alert triggers when any hostname is being reported by multiple different hosts. It:

1. **Identifies duplicate hostnames** - Groups hostnames and finds those reported by more than one host
2. **Returns conflicted hostnames** - Lists each distinct hostname that has conflicts
3. **Ready for Mission Portal** - Uses the correct schema (`hosts` view, `hostkey` identifier, `hostname` column)

## Key Technical Details

- **Table/View**: `hosts` (the public-facing view in Mission Portal)
- **Host Identifier**: `hostkey` (the unique identifier for each host)
- **Hostname Field**: `hostname` (derived from the `__inventory` table)
- **Alert Condition**: Query returns results when hostnames are duplicated across different hosts

The query has been verified against the CFEngine Mission Portal database schema documentation and is syntactically correct for PostgreSQL.