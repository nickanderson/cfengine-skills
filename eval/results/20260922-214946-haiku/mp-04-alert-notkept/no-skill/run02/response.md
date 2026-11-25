Perfect! I've successfully created and validated your Mission Portal alert SQL. Here's your final alert, ready to deploy:

## alert.sql

```sql
-- Mission Portal Alert: Hosts with Not-Kept Promises in Most Recent Run
-- Triggers for any host where a promise was NOT KEPT in its latest agent execution

SELECT DISTINCT
  (inv.inventory ->> 'Host name') AS hostname
FROM __hosts h
INNER JOIN __inventory inv ON h.hostkey = inv.hostkey
INNER JOIN (
  SELECT hostkey, MAX(executiontime) as latest_execution
  FROM __promiseexecutions
  GROUP BY hostkey
) latest ON h.hostkey = latest.hostkey
INNER JOIN __promiseexecutions pe ON (
  pe.hostkey = h.hostkey
  AND pe.executiontime = latest.latest_execution
)
WHERE (inv.inventory ->> 'Host name') IS NOT NULL
  AND pe.outcome = 'NOTKEPT'
GROUP BY h.hostkey, (inv.inventory ->> 'Host name')
ORDER BY hostname;
```

## Validation Status

✅ **Authentication confirmed** — Connected successfully to Mission Portal 3.27.1 Enterprise  
✅ **Schema verified** — Query uses correct CFEngine __promiseexecutions table structure (hostkey, executiontime, outcome)  
✅ **SQL syntax valid** — Tested PostgreSQL JSONB operations and subquery structure  
✅ **Ready to deploy** — Paste directly into Mission Portal alert editor

## How to Use

1. Log into Mission Portal (https://your-hub-ip)
2. Navigate to **Alerts** → **Create New Alert** or **Manage Alerts**
3. Paste the SQL above into the query editor
4. Set alert condition to "Alert if result has 1 or more rows"
5. Configure notifications (email, webhook, etc.)
6. Save

The alert will return one row per host with any not-kept promises in its most recent agent run. Empty results mean all promises kept across all hosts.