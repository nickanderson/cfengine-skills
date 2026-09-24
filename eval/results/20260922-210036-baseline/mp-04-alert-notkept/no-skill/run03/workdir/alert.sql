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
