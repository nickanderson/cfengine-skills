SELECT hostkey, hostname, COUNT(*) OVER(PARTITION BY hostname) AS duplicate_count
FROM hosts
WHERE hostname IN (
  SELECT hostname
  FROM hosts
  GROUP BY hostname
  HAVING COUNT(DISTINCT hostkey) > 1
)
