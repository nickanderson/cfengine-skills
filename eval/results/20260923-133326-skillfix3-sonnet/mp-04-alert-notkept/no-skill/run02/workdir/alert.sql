-- Mission Portal alert: hosts with a promise not kept in their most recent
-- cf-agent run.
--
-- promiseexecutions (view over __promiseexecutions) holds exactly one row per
-- promise reflecting the outcome from each host's most recently reported
-- cf-agent run (per the hub's own schema description: "Promises executed on
-- hosts during their last reported cf-agent run"). Filtering that view for
-- promiseoutcome = 'NOTKEPT' and joining to hosts for identifying info gives
-- one row per host per unkept promise in its latest run.
SELECT DISTINCT
    h.hostkey,
    h.hostname,
    h.ipaddress,
    h.lastreporttimestamp
FROM hosts h
JOIN promiseexecutions pe ON pe.hostkey = h.hostkey
WHERE pe.promiseoutcome = 'NOTKEPT'
ORDER BY h.hostname
