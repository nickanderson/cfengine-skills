Verified against the hub: `alert.sql` (as-is, comments and all) executes cleanly and correctly returns `hub.example.com`, the one host in this environment with an unkept promise from its latest run.

## Summary

I connected to the Mission Portal's `/api/query` endpoint (same query engine the alert editor uses) and inspected the hub's Postgres reporting schema:

- `__promiseexecutions` (queryable as view `promiseexecutions`) is documented in the hub's own schema comments as "Promises executed on hosts during their last reported cf-agent run" — one row per promise, reflecting only the latest run's outcome (as opposed to `__promiselog`, which is the full historical log of every NOTKEPT/REPAIRED event across all runs).
- Joining that to the `hosts` view gives host identity (hostname/IP) for each unkept promise.
- Note: a trailing `;` breaks queries against this API/alert engine, since it wraps your SQL in an outer `SELECT ... FROM (your_query) LIMIT n` — I removed it.

`alert.sql`:
```sql
-- Mission Portal alert: hosts with a promise not kept in their most recent
-- cf-agent run.
--
-- promiseexecutions (view over __promiseexecutions) holds exactly one row per
-- promise reflecting the outcome from each host's most recently reported
-- cf-agent run (per the hub's own schema description: "Promises executed on
-- hosts during their last reported cf-agent run"). Filtering that view for
-- promiseoutcome = 'NOTKEPT' and joining to hosts for identifying info gives
-- one row per host per unkept promise in its latest run.
SELECT DISTINCT
    h.hostkey,
    h.hostname,
    h.ipaddress,
    h.lastreporttimestamp
FROM hosts h
JOIN promiseexecutions pe ON pe.hostkey = h.hostkey
WHERE pe.promiseoutcome = 'NOTKEPT'
ORDER BY h.hostname
```