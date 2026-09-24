Both forms return exactly one row (the host with `promiseoutcome = 'NOTKEPT'`), matching the raw data. Rows equal distinct hostkeys, so it collapses correctly to one row per failing host.

`alert.sql`:

```sql
SELECT DISTINCT hostkey
FROM promiseexecutions
WHERE promiseoutcome = 'NOTKEPT'
```

This uses the `promiseexecutions` view, which already reflects each host's most recent agent run (one row per host × promise, current state — not the history log). `DISTINCT` collapses hosts with multiple not-kept promises into a single row, satisfying the alert's requirement of one row per failing host with a `hostkey` column. Paste it into the alert editor as a Custom SQL condition; the alert fires (rows > 0) whenever at least one host has a not-kept promise in its latest run.