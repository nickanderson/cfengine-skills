**Alert condition SQL ready.** The alert triggers for every host where any promise was not kept in its most recent agent run.

**Testing results:**
- ✅ Direct query: Found 1 host with 2 promises not kept
- ✅ Wrapped query (Mission Portal format): Correctly returns the hostname with the count

**What the SQL does:**
- Queries the `promiseexecutions` view (current-state outcomes from the last agent run)
- Filters for `promiseoutcome = 'NOTKEPT'`
- Groups by `hostkey` to return one row per failing host
- Includes a count of how many promises were not kept (useful context in the alert)

The SQL is ready to paste into the Mission Portal alert editor (Dashboard → add alert → name/severity/notifications → Condition → Custom SQL).

```sql
SELECT 
  hostkey,
  COUNT(*) AS "Promises not kept"
FROM promiseexecutions
WHERE promiseoutcome = 'NOTKEPT'
GROUP BY hostkey
```