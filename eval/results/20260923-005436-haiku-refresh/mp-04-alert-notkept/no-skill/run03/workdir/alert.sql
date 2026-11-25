-- CFEngine Enterprise Mission Portal Alert SQL
-- Trigger: Any host where a promise was not kept in the most recent agent run
--
-- PRIMARY QUERY (use this first):
-- This query joins hosts with promise executions to find hosts with unfulfilled promises
-- in their most recent agent run window

SELECT DISTINCT h.hostkey, h.hostname
FROM hosts h
WHERE h.hostkey IN (
  SELECT DISTINCT pe.hostkey
  FROM promise_executions pe
  WHERE pe.outcome = 'not_kept'
    AND pe.timestamp >= (
      SELECT MAX(timestamp)
      FROM promise_executions
      WHERE hostkey = h.hostkey
    ) - INTERVAL '1 hour'
)
AND h.active = true
ORDER BY h.hostname;
