-- Mission Portal alert condition:
-- Trigger for every host whose hostname is also reported by a different host
-- (i.e. two or more distinct hostkeys reporting the same hostname).
SELECT hostkey, hostname, ipaddress
FROM hosts
WHERE hostname IN (
    SELECT hostname
    FROM hosts
    GROUP BY hostname
    HAVING COUNT(DISTINCT hostkey) > 1
)
ORDER BY hostname, hostkey;
