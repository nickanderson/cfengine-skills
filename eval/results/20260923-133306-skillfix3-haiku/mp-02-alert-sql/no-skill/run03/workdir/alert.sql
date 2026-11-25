SELECT hostname, COUNT(DISTINCT hostkey) as duplicate_host_count, array_agg(DISTINCT hostkey ORDER BY hostkey) as reporting_hostkeys
FROM hosts
GROUP BY hostname
HAVING COUNT(DISTINCT hostkey) > 1
ORDER BY hostname
