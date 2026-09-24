Perfect! The SQL is working correctly. Both tests passed:

- **Raw SQL**: Returns 1 row with the hostkey for a host that had a NOTKEPT promise
- **Wrapped form** (as Mission Portal will use it): Successfully joins with the hosts table and displays the hostname

The alert condition is ready. Here's the final SQL for your alert:

```sql
SELECT DISTINCT hostkey
FROM promiseexecutions
WHERE promiseoutcome = 'NOTKEPT'
```

**How it works:**
- Queries the `promiseexecutions` view for promises in the most recent agent run
- Filters for outcomes of `'NOTKEPT'` (the three possible values are `KEPT`, `REPAIRED`, `NOTKEPT`)
- Uses `DISTINCT` to return one row per host, so a host with multiple failed promises only triggers the alert once
- Returns the required `hostkey` column for Mission Portal to join with the hosts table

The file `alert.sql` is ready to paste into the Mission Portal alert editor under Dashboard → add alert → Custom SQL condition.