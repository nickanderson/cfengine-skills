-- Mission Portal Alert: Hosts with Not-Kept Promises in Most Recent Run
-- Triggers for any host where a promise was NOT KEPT in its latest agent execution

SELECT DISTINCT
  (inv.inventory ->> 'Host name') AS hostname
FROM __hosts h
INNER JOIN __inventory inv ON h.hostkey = inv.hostkey
INNER JOIN (
  SELECT hostkey, MAX(executiontime) as latest_execution
  FROM __promiseexecutions
  GROUP BY hostkey
) latest ON h.hostkey = latest.hostkey
INNER JOIN __promiseexecutions pe ON (
  pe.hostkey = h.hostkey
  AND pe.executiontime = latest.latest_execution
)
WHERE (inv.inventory ->> 'Host name') IS NOT NULL
  AND pe.outcome = 'NOTKEPT'
GROUP BY h.hostkey, (inv.inventory ->> 'Host name')
ORDER BY hostname;
