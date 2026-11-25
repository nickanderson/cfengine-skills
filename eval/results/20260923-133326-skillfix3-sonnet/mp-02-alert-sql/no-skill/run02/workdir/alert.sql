-- Alert condition: fires for every host whose hostname is also being
-- reported by at least one other host (i.e. the hostname is not unique
-- across distinct hostkeys).
SELECT hostkey, hostname, ipaddress, lastreporttimestamp
FROM hosts
WHERE hostname IN (
  SELECT hostname
  FROM hosts
  GROUP BY hostname
  HAVING COUNT(DISTINCT hostkey) > 1
)
ORDER BY hostname, hostkey
