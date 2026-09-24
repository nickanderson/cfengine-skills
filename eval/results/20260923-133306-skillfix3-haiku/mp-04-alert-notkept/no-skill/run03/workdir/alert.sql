-- Mission Portal Alert: Hosts with Promises Not Kept
-- Triggers when any host has promises not kept in its most recent agent run.
-- Note: This query uses the __promiselog_NOTKEPT_* tables which are partitioned by date.
-- Update the date range periodically to include recent tables as new days are added.
-- Current range covers the last 10 days of available data.

SELECT DISTINCT h.hostkey, h.hostname
FROM hosts h
WHERE EXISTS (
  SELECT 1
  FROM (
    -- Union all recent NOTKEPT promise log tables
    SELECT DISTINCT hostkey FROM "__promiselog_NOTKEPT_2026-09-16" UNION ALL
    SELECT DISTINCT hostkey FROM "__promiselog_NOTKEPT_2026-09-17" UNION ALL
    SELECT DISTINCT hostkey FROM "__promiselog_NOTKEPT_2026-09-18" UNION ALL
    SELECT DISTINCT hostkey FROM "__promiselog_NOTKEPT_2026-09-19" UNION ALL
    SELECT DISTINCT hostkey FROM "__promiselog_NOTKEPT_2026-09-20" UNION ALL
    SELECT DISTINCT hostkey FROM "__promiselog_NOTKEPT_2026-09-21" UNION ALL
    SELECT DISTINCT hostkey FROM "__promiselog_NOTKEPT_2026-09-22" UNION ALL
    SELECT DISTINCT hostkey FROM "__promiselog_NOTKEPT_2026-09-23" UNION ALL
    SELECT DISTINCT hostkey FROM "__promiselog_NOTKEPT_2026-09-24" UNION ALL
    SELECT DISTINCT hostkey FROM "__promiselog_NOTKEPT_2026-09-25"
  ) notkept
  WHERE notkept.hostkey = h.hostkey
)
ORDER BY h.hostname;
