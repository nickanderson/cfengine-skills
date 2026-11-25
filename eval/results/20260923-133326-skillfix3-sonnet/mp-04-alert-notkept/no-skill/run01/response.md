I investigated the hub's reporting schema live (via `POST $MP_URL/api/query`, since `information_schema`/`pg_catalog` access is blocked) and confirmed:

- `Hosts` has `hostkey`, `hostname`, etc.
- `PromiseExecutions` has `hostkey`, `stackpath`, `promiseoutcome` (`KEPT`/`REPAIRED`/`NOTKEPT`), `changetimestamp`.
- It's a **delta-reported** table: a promise only gets a new row when its outcome *changes* from what the hub last knew (verified — one host had 49 rows all sharing a single timestamp from its first run despite reporting for hours afterward, since nothing changed). So "most recent run's outcome" for a given promise means its row with the greatest `changetimestamp` for that `(hostkey, stackpath)`.
- Mission Portal's custom SQL alert condition requires the result set to include a `hostkey` column.

The query in `alert.sql` joins `Hosts` to `PromiseExecutions`, keeps only rows where a promise's latest recorded outcome is `NOTKEPT` (filtering out ones later superseded by a `KEPT`/`REPAIRED` row), and returns each affected host once. I ran it against the live hub and it correctly returned the one host (`hub.example.com`) that currently has unfixed `NOTKEPT` promises.

```sql
-- Mission Portal custom SQL alert condition
-- Triggers for every host where any promise was NOT kept (PromiseOutcome = 'NOTKEPT')
-- in its most recent agent run.
--
-- PromiseExecutions is only written to on a per-promise CHANGE (CFEngine's hub
-- only re-reports a promise when its outcome differs from what was last known),
-- so the "current" state of a given promise is its row with the greatest
-- ChangeTimeStamp for that HostKey + StackPath. We compare each NOTKEPT row's
-- timestamp against that per-promise maximum so a promise that was later fixed
-- (superseded by a newer KEPT/REPAIRED row) does not keep triggering the alert.
--
-- Mission Portal requires custom SQL alert conditions to return a `hostkey`
-- column; `hostname` is included for readability in the alert output.

SELECT DISTINCT h.hostkey AS hostkey, h.hostname AS hostname
FROM Hosts h
JOIN PromiseExecutions pe ON pe.hostkey = h.hostkey
WHERE pe.promiseoutcome = 'NOTKEPT'
  AND pe.changetimestamp = (
    SELECT MAX(pe2.changetimestamp)
    FROM PromiseExecutions pe2
    WHERE pe2.hostkey = pe.hostkey
      AND pe2.stackpath = pe.stackpath
  )
ORDER BY h.hostname;
```