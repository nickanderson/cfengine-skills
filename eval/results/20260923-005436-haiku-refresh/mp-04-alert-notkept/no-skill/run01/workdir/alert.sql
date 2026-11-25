-- Alert: Hosts with Unmet Promises (Not Kept) in Most Recent Agent Run
-- =====================================================================
--
-- PURPOSE: Triggers for every host where any promise was not kept in its latest
--          agent execution, enabling rapid identification of compliance failures.
--
-- LOGIC:
--   1. Join Hosts table with Promise_not_kept table using hostkey
--   2. For each host, find the most recent promise failure timestamp
--   3. Return all hosts that have promise failures in their latest run
--
-- TABLE NOTES:
--   - Promise_not_kept: Contains rows for each promise marked "not kept"
--     Columns: hostkey, changetimestamp (timestamp of the report)
--   - Hosts: Standard hosts table with connection status
--     Columns: hostkey, hostname, ipaddress, lastreporttimestamp
--
-- =====================================================================
-- PRIMARY QUERY (Most Common in CFEngine Enterprise 3.15+)
-- =====================================================================

SELECT DISTINCT
    h.hostkey,
    h.hostname,
    h.ipaddress,
    h.lastreporttimestamp as most_recent_agent_run
FROM Hosts h
INNER JOIN Promise_not_kept pnk ON h.hostkey = pnk.hostkey
WHERE pnk.changetimestamp = (
    SELECT MAX(changetimestamp)
    FROM Promise_not_kept
    WHERE hostkey = h.hostkey
)
ORDER BY h.hostname;


-- =====================================================================
-- ALTERNATIVE QUERIES (if above table names don't match your environment)
-- =====================================================================

-- Alternative 1: If table uses underscore naming (lowercase)
-- SELECT DISTINCT
--     h.hostkey,
--     h.hostname,
--     h.ipaddress,
--     h.lastreporttimestamp as most_recent_agent_run
-- FROM Hosts h
-- INNER JOIN promise_not_kept pnk ON h.hostkey = pnk.hostkey
-- WHERE pnk.changetimestamp = (
--     SELECT MAX(changetimestamp)
--     FROM promise_not_kept
--     WHERE hostkey = h.hostkey
-- )
-- ORDER BY h.hostname;


-- Alternative 2: If table tracks promise status (kept/not_kept/repaired)
-- SELECT DISTINCT
--     h.hostkey,
--     h.hostname,
--     h.ipaddress,
--     h.lastreporttimestamp as most_recent_agent_run
-- FROM Hosts h
-- INNER JOIN promise_execution pe ON h.hostkey = pe.hostkey
-- WHERE pe.status = 'not_kept'
--   AND pe.timestamp = (
--       SELECT MAX(timestamp)
--       FROM promise_execution
--       WHERE hostkey = h.hostkey
--   )
-- ORDER BY h.hostname;


-- Alternative 3: If using older CFEngine version with different table name
-- SELECT DISTINCT
--     h.hostkey,
--     h.hostname,
--     h.ipaddress,
--     h.lastreporttimestamp as most_recent_agent_run
-- FROM Hosts h
-- WHERE EXISTS (
--     SELECT 1
--     FROM PromiseNotKept pnk
--     WHERE pnk.hostkey = h.hostkey
--       AND pnk.timestamp >= h.lastreporttimestamp - INTERVAL '1 hour'
-- )
-- ORDER BY h.hostname;


-- =====================================================================
-- HOW TO USE THIS ALERT
-- =====================================================================
-- 1. Copy the PRIMARY QUERY above into the Mission Portal alert editor
-- 2. If the table name doesn't exist, try each ALTERNATIVE QUERY
-- 3. To find the correct table name:
--    - In the alert editor, test the query with different table names
--    - Check CFEngine Enterprise documentation for your version
--    - Query information_schema.tables to list all available tables
-- 4. Once working, the alert will automatically execute on schedule and
--    notify administrators of any hosts with unmet promises
