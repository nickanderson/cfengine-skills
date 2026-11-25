I verified this against the live hub via the Mission Portal query API (`/api/query`): it correctly returned the one host currently affected (`hub.example.com`, 192.168.56.2), matching the two `NOTKEPT` promise rows I found by hand in `promiseexecutions`.

Key finding: `promiseexecutions` is a current-state table — each host has exactly one `changetimestamp` at any time (its latest report), unlike `promiselog`/`__promiselog_NOTKEPT_*` which are historical logs. So this is the right table to query for "most recent agent run," and the `max(changetimestamp)` self-join makes that explicit rather than relying on an implicit assumption about the table's ingestion behavior.

```sql
-- Mission Portal alert condition:
-- Trigger for every host that has at least one promise with outcome
-- NOTKEPT in its most recent agent run (report).
--
-- `promiseexecutions` holds only the latest evaluation of every promise
-- for each host (one changetimestamp per hostkey, replaced on each new
-- report), so filtering to each host's own max(changetimestamp) pins
-- this to "most recent run" even if that assumption ever changes.
SELECT DISTINCT
    h.hostkey,
    h.hostname,
    h.ipaddress
FROM promiseexecutions pe
JOIN hosts h ON h.hostkey = pe.hostkey
WHERE pe.promiseoutcome = 'NOTKEPT'
  AND pe.changetimestamp = (
        SELECT max(pe2.changetimestamp)
        FROM promiseexecutions pe2
        WHERE pe2.hostkey = pe.hostkey
      )
ORDER BY h.hostname;
```

Saved to `alert.sql`, ready to paste into the alert editor.