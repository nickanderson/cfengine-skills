Done! Your alert condition is ready. Here's the final SQL in `alert.sql`:

```sql
SELECT DISTINCT hostkey
FROM promiseexecutions
WHERE promiseoutcome = 'NOTKEPT'
```

**Test results:**
- ✅ Raw query: Returns 1 host (`hub.example.com`) that has unmet promises
- ✅ Wrapped query (host list display): Correctly joins with the hosts table and shows hostname + hostkey

**What it does:**
- Queries the `promiseexecutions` table for all promises with outcome `NOTKEPT`
- Uses `SELECT DISTINCT hostkey` to return one row per affected host (no duplicates even if multiple promises on the same host failed)
- Triggers the alert whenever any host has unmet promises in its most recent agent run

You can now paste this SQL directly into Mission Portal's dashboard alert editor as a Custom SQL condition.