SELECT h.hostkey, h.hostname
FROM hosts h
JOIN (SELECT hostname FROM hosts GROUP BY hostname HAVING count(*) > 1) d USING (hostname)
