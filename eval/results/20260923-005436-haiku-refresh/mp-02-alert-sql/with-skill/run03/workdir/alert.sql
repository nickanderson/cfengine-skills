WITH duplicate_hostnames AS (
  SELECT hostname
  FROM hosts
  GROUP BY hostname
  HAVING count(DISTINCT hostkey) > 1
)
SELECT h.hostkey
FROM hosts h
WHERE h.hostname IN (SELECT hostname FROM duplicate_hostnames)
