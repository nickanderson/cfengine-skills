SELECT hostkey
FROM hosts h
WHERE EXISTS (
  SELECT 1
  FROM hosts h2
  WHERE h2.hostname = h.hostname
    AND h2.hostkey != h.hostkey
)
