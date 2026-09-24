SELECT hostkey, hostname
FROM hosts
WHERE hostname IN (
  SELECT hostname
  FROM hosts
  GROUP BY hostname
  HAVING count(*) > 1
)
ORDER BY hostname, hostkey