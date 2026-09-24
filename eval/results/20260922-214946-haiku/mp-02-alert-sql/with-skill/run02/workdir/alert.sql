SELECT hostkey, hostname
FROM hosts
WHERE hostname IN (
  SELECT hostname
  FROM hosts
  GROUP BY hostname
  HAVING COUNT(DISTINCT hostkey) > 1
)
