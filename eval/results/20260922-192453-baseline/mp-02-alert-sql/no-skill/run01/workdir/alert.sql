-- Mission Portal dashboard alert condition
-- Triggers for every host whose hostname is also reported by a different host
-- (i.e. duplicate hostnames across distinct HostKeys).
-- Must return a hostkey column per Mission Portal custom-condition requirements.

SELECT HostKey, HostName
FROM Hosts h
WHERE EXISTS (
    SELECT 1
    FROM Hosts h2
    WHERE h2.HostName = h.HostName
      AND h2.HostKey <> h.HostKey
);
