-- Alert: Hosts with promises not kept in most recent agent run
-- Identifies all hosts with NOT KEPT promises by checking for entries in the
-- NOTKEPT promise logs for hosts that have reported status.

WITH latest_status AS (
    -- Get the most recent status report timestamp for each host
    SELECT host, MAX(ts) as latest_ts FROM Status GROUP BY host
)
SELECT DISTINCT latest_status.host
FROM latest_status
WHERE EXISTS (
    -- Check if this host has any NOT KEPT promises in recent logs
    SELECT 1 FROM (
        SELECT hostkey, changetimestamp FROM "__promiselog_NOTKEPT_2026-09-25"
        UNION ALL
        SELECT hostkey, changetimestamp FROM "__promiselog_NOTKEPT_2026-09-24"
        UNION ALL
        SELECT hostkey, changetimestamp FROM "__promiselog_NOTKEPT_2026-09-23"
        UNION ALL
        SELECT hostkey, changetimestamp FROM "__promiselog_NOTKEPT_2026-09-22"
        UNION ALL
        SELECT hostkey, changetimestamp FROM "__promiselog_NOTKEPT_2026-09-21"
        UNION ALL
        SELECT hostkey, changetimestamp FROM "__promiselog_NOTKEPT_2026-09-20"
        UNION ALL
        SELECT hostkey, changetimestamp FROM "__promiselog_NOTKEPT_2026-09-19"
        UNION ALL
        SELECT hostkey, changetimestamp FROM "__promiselog_NOTKEPT_2026-09-18"
        UNION ALL
        SELECT hostkey, changetimestamp FROM "__promiselog_NOTKEPT_2026-09-17"
        UNION ALL
        SELECT hostkey, changetimestamp FROM "__promiselog_NOTKEPT_2026-09-16"
    ) AS recent_notkept
    WHERE hostkey = latest_status.host
)
