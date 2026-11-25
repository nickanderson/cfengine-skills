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
