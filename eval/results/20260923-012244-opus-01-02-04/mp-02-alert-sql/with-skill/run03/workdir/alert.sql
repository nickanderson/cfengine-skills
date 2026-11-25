/* Hosts whose hostname is also reported by at least one other host (different hostkey).
   Hostnames compared case-insensitively; hosts with no hostname are ignored. */
SELECT h.hostkey,
       h.hostname AS "Reported hostname",
       h.lastreporttimestamp AS "Last report"
FROM hosts AS h
WHERE coalesce(h.hostname, '') <> ''
  AND EXISTS (
        SELECT 1
        FROM hosts AS other
        WHERE lower(other.hostname) = lower(h.hostname)
          AND other.hostkey <> h.hostkey
      )
