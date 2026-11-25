SELECT hostkey, hostname AS "Duplicate hostname"
FROM hosts
WHERE hostname IN (
  SELECT hostname
  FROM hosts
  GROUP BY hostname
  HAVING count(*) > 1
)
