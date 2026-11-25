SELECT DISTINCT h1.hostkey
FROM hosts h1
WHERE h1.hostname IN (
  SELECT hostname
  FROM hosts
  WHERE hostname IS NOT NULL
  GROUP BY hostname
  HAVING COUNT(DISTINCT hostkey) > 1
)