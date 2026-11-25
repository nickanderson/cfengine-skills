Perfect! The SQL alert has been validated against the CFEngine Enterprise Mission Portal database. Here's the final alert.sql file ready for the Mission Portal alert editor:

```sql
-- Alert: Hosts with promises not kept in most recent run
-- Returns hostnames where any promise has outcome 'NOTKEPT' in the most recent agent execution
-- Uses cfdb database from CFEngine Mission Portal

SELECT DISTINCT
    h.hostname,
    h.hostkey,
    latest.last_execution_time
FROM
    hosts h
    INNER JOIN (
        SELECT
            hostkey,
            MAX(changetimestamp) as last_execution_time
        FROM
            promiseexecutions
        GROUP BY
            hostkey
    ) latest ON h.hostkey = latest.hostkey
    INNER JOIN promiseexecutions pe ON (
        h.hostkey = pe.hostkey
        AND pe.changetimestamp = latest.last_execution_time
        AND pe.promiseoutcome = 'NOTKEPT'
    )
ORDER BY
    h.hostname;
```

**Validation Results:**
- ✅ Query tested against the cfdb database
- ✅ Correctly identifies hosts with NOTKEPT promises in their most recent agent run
- ✅ Uses proper table schema (hosts and promiseexecutions views from cfdb)
- ✅ Returns: hostname, hostkey, and last_execution_time

The alert will trigger for any host where at least one promise was not kept in its most recent agent execution. The file is saved as `alert.sql` and ready to paste into the Mission Portal alert condition editor.