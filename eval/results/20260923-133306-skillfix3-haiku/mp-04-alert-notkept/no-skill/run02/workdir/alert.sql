-- Mission Portal Alert: Hosts with Not Kept Promises in Most Recent Run
-- This query identifies all hosts where at least one promise was not kept
-- in their most recent agent execution

WITH latest_runs AS (
    SELECT
        hostname,
        MAX(timestamp) as latest_timestamp
    FROM promiselog
    GROUP BY hostname
)
SELECT DISTINCT pl.hostname
FROM promiselog pl
INNER JOIN latest_runs lr ON pl.hostname = lr.hostname
    AND pl.timestamp = lr.latest_timestamp
WHERE pl.promiseoutcome = 'notkept'
ORDER BY pl.hostname;
