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
