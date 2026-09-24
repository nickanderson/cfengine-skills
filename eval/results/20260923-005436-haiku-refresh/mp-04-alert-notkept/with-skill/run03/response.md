Perfect! The alert SQL has been validated successfully. Here's the summary:

**Alert condition (alert.sql):**
```sql
SELECT DISTINCT hostkey
FROM promiseexecutions
WHERE promiseoutcome = 'NOTKEPT'
```

**Test results:**
- ✅ Direct query: Returns 1 host with unkept promises
- ✅ UI wrapped form: Correctly joins with hosts table, showing the hostname

The alert will trigger for any host where `promiseexecutions` contains at least one row with `promiseoutcome = 'NOTKEPT'`. This captures every host that had any promise not kept in its most recent agent run.

The file is ready to copy into the Mission Portal alert editor (Dashboard → add alert → condition type: Custom SQL).