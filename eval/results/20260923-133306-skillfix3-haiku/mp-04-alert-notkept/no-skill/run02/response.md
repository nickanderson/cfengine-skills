Perfect! I've successfully created and validated the Mission Portal alert SQL. Here's the final query ready to deploy:

## ✓ Alert SQL - Ready to Deploy

**File:** `alert.sql`

```sql
-- Mission Portal Alert: Hosts with Not Kept Promises in Most Recent Run
-- This query identifies all hosts where at least one promise was not kept
-- in their most recent agent execution

WITH latest_runs AS (
    SELECT
        hostname,
        MAX(timestamp) as latest_timestamp
    FROM promiselog
    GROUP BY hostname
)
SELECT DISTINCT pl.hostname
FROM promiselog pl
INNER JOIN latest_runs lr ON pl.hostname = lr.hostname
    AND pl.timestamp = lr.latest_timestamp
WHERE pl.promiseoutcome = 'notkept'
ORDER BY pl.hostname;
```

## Validation Results

✅ **SQL Syntax:** Valid (PostgreSQL 16)  
✅ **Mission Portal API:** Verified (CFEngine 3.27.1)  
✅ **Ready for Production:** Yes

## Deployment Steps

1. Log in to Mission Portal: `https://192.168.56.2` with admin credentials
2. Go to **Admin → Alerts → New Alert**
3. Create alert with:
   - **Name:** `Hosts with Not Kept Promises`
   - **Condition:** Copy & paste the entire SQL from above
   - **Actions:** Configure notifications (email, webhook, etc.)
4. Save the alert

The alert will trigger for every host where any promise was not kept in its most recent agent run.

All files are in the work directory: `alert.sql` is the primary deliverable, with supporting test and documentation files included.