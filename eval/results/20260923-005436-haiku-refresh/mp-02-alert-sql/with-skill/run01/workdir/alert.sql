SELECT h.hostkey
FROM hosts h
WHERE h.hostname IN (
  SELECT hostname
  FROM hosts
  WHERE hostname IS NOT NULL
  GROUP BY hostname
  HAVING COUNT(DISTINCT hostkey) > 1
)