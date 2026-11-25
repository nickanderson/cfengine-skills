I verified this against the live hub via `POST $MP_URL/api/query`. Key findings that shaped the query:

- `promiselog` only logs promises whose outcome is `REPAIRED` or `NOTKEPT` — kept promises never get a row, so "not kept" simply means `promiseoutcome = 'NOTKEPT'`.
- There's no run/execution id column, so "most recent agent run" per host is approximated by taking rows within 120s of that host's own max `changetimestamp` (observed same-run spread was a few seconds; runs on this hub repeat every ~5 minutes).
- Running it now correctly flags `hub.example.com`, which currently has a `NOTKEPT` promise in its latest run, and correctly excludes hosts with no unkept promises recently.

`alert.sql`:

```sql
-- Mission Portal alert: hosts with a NOTKEPT promise in their most recent agent run.
--
-- promiselog only stores rows for promises that were NOT kept (REPAIRED or
-- NOTKEPT); KEPT promises are never logged. There is no run/execution id, so
-- "most recent agent run" is approximated as: all promiselog rows for a host
-- within 120 seconds of that host's own latest changetimestamp. Observed
-- run-internal spread on this hub is a few seconds, and runs are ~5 minutes
-- apart, so 120s safely groups one run without bleeding into the previous
-- one. Adjust the interval if your environment's agent execution interval
-- differs.
SELECT DISTINCT
    h.hostname,
    h.ipaddress,
    p.hostkey
FROM promiselog p
JOIN (
    SELECT hostkey, MAX(changetimestamp) AS max_ts
    FROM promiselog
    GROUP BY hostkey
) latest
    ON p.hostkey = latest.hostkey
    AND p.changetimestamp >= latest.max_ts - INTERVAL '120 seconds'
JOIN hosts h
    ON h.hostkey = p.hostkey
WHERE p.promiseoutcome = 'NOTKEPT'
ORDER BY h.hostname;
```