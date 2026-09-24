SELECT DISTINCT hostkey
FROM hosts
WHERE hostname IN (
  SELECT hostname
  FROM hosts
  WHERE hostname IS NOT NULL
  GROUP BY hostname
  HAVING count(DISTINCT hostkey) > 1
)
AND hostname IS NOT NULL