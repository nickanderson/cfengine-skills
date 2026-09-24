Verified against the hub: `promiseexecutions` holds only each host's most recent run outcomes, so filtering on `promiseoutcome = 'NOTKEPT'` with `DISTINCT hostkey` gives exactly one row per affected host — confirmed both as a standalone query (1 row) and wrapped exactly the way Mission Portal wraps custom-SQL alert conditions (still 1 row, correct `hostkey`/hostname join).

`alert.sql`:
```sql
SELECT DISTINCT hostkey
FROM promiseexecutions
WHERE promiseoutcome = 'NOTKEPT'
```

Paste this into the alert's Custom SQL condition field as-is (no trailing `;`). The alert will trigger with a failing-host count equal to the number of hosts that had at least one not-kept promise in their latest agent run.