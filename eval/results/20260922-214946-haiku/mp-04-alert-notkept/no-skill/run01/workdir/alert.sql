-- Alert: Hosts with promises not kept in most recent run
-- Returns hostnames where any promise has outcome 'NOTKEPT' in the most recent agent execution
-- Uses cfdb database from CFEngine Mission Portal

SELECT DISTINCT
    h.hostname,
    h.hostkey,
    latest.last_execution_time
FROM
    hosts h
    INNER JOIN (
        SELECT
            hostkey,
            MAX(changetimestamp) as last_execution_time
        FROM
            promiseexecutions
        GROUP BY
            hostkey
    ) latest ON h.hostkey = latest.hostkey
    INNER JOIN promiseexecutions pe ON (
        h.hostkey = pe.hostkey
        AND pe.changetimestamp = latest.last_execution_time
        AND pe.promiseoutcome = 'NOTKEPT'
    )
ORDER BY
    h.hostname;
