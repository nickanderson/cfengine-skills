I verified this directly against the hub via `/api/query`: the schema uses a `hosts` table (`hostkey`, `hostname`, ...) and a `PromiseExecutions` table that holds each promise's outcome (`KEPT`/`REPAIRED`/`NOTKEPT`) as of its latest evaluation, with all promises from one run sharing a single `changetimestamp` per host. Running it live returned exactly one host currently affected — `hub.example.com`, with two `NOTKEPT` promises (`CFEngine Recommendations`, `/var/cfengine/state/pg/data/postgresql.conf`) both timestamped at that host's most recent run.

```sql
-- Mission Portal alert condition:
-- Triggers for every host that had at least one promise with outcome
-- NOTKEPT during its most recent agent run.
--
-- PromiseExecutions holds the state of every promise as of its most
-- recent evaluation (KEPT/REPAIRED/NOTKEPT); all promises evaluated in
-- the same run share a single changetimestamp for a given host, so
-- matching pe.changetimestamp to that host's MAX(changetimestamp)
-- isolates the most recent run.
SELECT h.hostkey, h.hostname
FROM PromiseExecutions pe
JOIN hosts h
  ON h.hostkey = pe.hostkey
JOIN (
    SELECT hostkey, MAX(changetimestamp) AS last_run
    FROM PromiseExecutions
    GROUP BY hostkey
) latest
  ON latest.hostkey = pe.hostkey
 AND latest.last_run = pe.changetimestamp
WHERE pe.promiseoutcome = 'NOTKEPT'
GROUP BY h.hostkey, h.hostname
```

Saved to `alert.sql`, ready to paste into the alert editor.