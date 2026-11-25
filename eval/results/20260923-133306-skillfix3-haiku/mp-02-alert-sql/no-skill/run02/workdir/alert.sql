SELECT hostname
FROM hosts
WHERE hostname IS NOT NULL
  AND hostname != ''
GROUP BY hostname
HAVING COUNT(DISTINCT hostkey) > 1
ORDER BY hostname;
