-- Alert: Hosts with Any Promise Not Kept in Most Recent Agent Run
-- ==================================================================
--
-- PURPOSE: Triggers for every host where any promise was not kept in its
--          most recent agent run, enabling rapid identification of
--          compliance failures.
--
-- LOGIC:
--   1. For each host, find the most recent agent run timestamp from
--      the promise executions table
--   2. Check if that host has any promise outcomes marked 'not_kept'
--      in that most recent run
--   3. Return all such hosts
--

SELECT DISTINCT
    h.hostkey,
    h.ipaddress,
    h.lastreporttimestamp
FROM __hosts h
WHERE EXISTS (
    SELECT 1
    FROM __promiseexecutions pe
    WHERE pe.hostkey = h.hostkey
      AND pe.promiseoutcome = 'not_kept'
      AND pe.changetimestamp = (
          SELECT MAX(changetimestamp)
          FROM __promiseexecutions
          WHERE hostkey = h.hostkey
      )
)
ORDER BY h.ipaddress;
