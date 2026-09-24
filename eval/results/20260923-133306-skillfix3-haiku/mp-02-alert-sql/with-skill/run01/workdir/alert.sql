SELECT DISTINCT h.hostkey
FROM hosts h
WHERE h.hostname IN (
  SELECT hostname
  FROM hosts
  GROUP BY hostname
  HAVING count(*) > 1
)