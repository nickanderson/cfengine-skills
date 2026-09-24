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
