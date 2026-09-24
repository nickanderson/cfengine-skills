SELECT hostname, COUNT(DISTINCT hostkey) as num_hosts
FROM hosts
WHERE hostname IS NOT NULL AND hostname != ''
GROUP BY hostname
HAVING COUNT(DISTINCT hostkey) > 1
ORDER BY num_hosts DESC, hostname
