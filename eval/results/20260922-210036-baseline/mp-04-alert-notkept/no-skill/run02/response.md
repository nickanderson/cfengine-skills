I verified this against the live hub (via the Mission Portal `/api/query` endpoint using `$MP_URL`/`$MP_USER`/`$MP_PASSWORD`), where it correctly returned the one host (`hub.example.com`) whose latest logged run includes a `NOTKEPT` promise, and excluded the other two hosts that have never had a non-kept promise.

Key schema findings from probing the hub:
- `hosts(hostkey, hostname, ...)` and `promiselog(hostkey, changetimestamp, promiseoutcome, ...)` are the queryable tables (most others, e.g. `software`, `variables`, `events`, are "restricted database resources" and blocked from custom queries).
- `promiselog` only records `REPAIRED`/`NOTKEPT` outcomes — kept promises aren't logged at all — so it's already the right source for this alert.
- Promises from the same agent run don't share one exact timestamp (each is stamped when evaluated, so entries within one run can differ by a few seconds), which is why the query uses a 120-second window off each host's latest entry rather than exact-equality on `MAX(changetimestamp)`.
- The alert query API rejects a trailing semicolon (returns a generic error), so the file omits it — worth remembering when pasting into the editor.

```sql
-- Mission Portal alert: hosts with a promise not kept in their most recent agent run.
--
-- promiselog only ever contains REPAIRED/NOTKEPT entries (kept promises are
-- never logged), and entries from the same run can differ by a few seconds
-- (each promise is timestamped when it was evaluated, not with one shared
-- run start time). So "most recent run" is approximated as: all promiselog
-- rows for a host within 120 seconds of that host's latest logged entry.
-- 120s is comfortably below typical agent run intervals (minutes) while
-- covering normal in-run timestamp jitter.
--
-- Note: no trailing semicolon -- the Mission Portal query API rejects it.
SELECT DISTINCT h.hostname, h.hostkey
FROM promiselog p
JOIN hosts h ON h.hostkey = p.hostkey
WHERE p.promiseoutcome = 'NOTKEPT'
  AND p.changetimestamp >= (
        SELECT MAX(p2.changetimestamp) - INTERVAL '120 seconds'
        FROM promiselog p2
        WHERE p2.hostkey = p.hostkey
      )
ORDER BY h.hostname
```