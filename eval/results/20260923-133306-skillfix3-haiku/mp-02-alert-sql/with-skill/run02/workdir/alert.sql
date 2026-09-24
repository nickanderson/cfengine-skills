SELECT DISTINCT h1.hostkey, h1.hostname
FROM hosts h1
WHERE EXISTS (
  SELECT 1 FROM hosts h2
  WHERE h1.hostname = h2.hostname
  AND h1.hostkey != h2.hostkey
)
