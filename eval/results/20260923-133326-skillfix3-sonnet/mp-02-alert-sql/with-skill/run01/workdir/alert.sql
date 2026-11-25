SELECT hostkey
FROM hosts
WHERE hostname IN (
  SELECT hostname
  FROM hosts
  GROUP BY hostname
  HAVING count(DISTINCT hostkey) > 1
)
