Perfect! ✓ Both tests pass. The SQL correctly:
- Returns 1 host with unkept promises in the status check (alert triggers when `rowCount > 0`)
- Works with Mission Portal's wrapper to display failing hosts with their hostnames

Here's your alert SQL, ready to paste into the Dashboard alert editor:

```sql
SELECT DISTINCT hostkey
FROM promiseexecutions
WHERE promiseoutcome = 'NOTKEPT'
```

**To create the alert in Mission Portal:**
1. Go to Dashboard → add alert
2. Set Condition type to **Custom SQL**
3. Paste the SQL above
4. Set Host scope and notifications as desired
5. Save

The alert will trigger whenever any host has a promise with outcome `NOTKEPT` in its reporting data, and the alert details will show the affected host(s) with their names.