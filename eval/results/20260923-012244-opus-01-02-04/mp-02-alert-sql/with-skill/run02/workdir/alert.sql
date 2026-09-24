/* Hosts whose hostname is also reported by at least one other host (different hostkey).
   Hostnames are compared case-insensitively; hosts with no hostname are ignored. */
SELECT h.hostkey,
       h.ipaddress AS "IP address",
       h.lastreporttimestamp AS "Last report collected"
FROM hosts h
WHERE COALESCE(h.hostname, '') <> ''
  AND EXISTS (
        SELECT 1
        FROM hosts o
        WHERE lower(o.hostname) = lower(h.hostname)
          AND o.hostkey <> h.hostkey
      )
