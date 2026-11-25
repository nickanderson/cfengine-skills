-- Mission Portal alert condition:
-- Triggers for every host whose hostname is also reported by a different
-- host (i.e. two or more distinct host keys sharing the same hostname).
SELECT
    h.hostkey,
    h.hostname,
    h.ipaddress
FROM hosts h
WHERE EXISTS (
    SELECT 1
    FROM hosts h2
    WHERE h2.hostname = h.hostname
      AND h2.hostkey <> h.hostkey
)
ORDER BY h.hostname;
