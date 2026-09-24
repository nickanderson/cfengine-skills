I verified the query directly against the hub's `/api/query` endpoint (Postgres `Hosts` table: `HostKey`, `HostName`, `IPAddress`, `LastReportTimeStamp`, `FirstReportTimeStamp`). It correctly returned the 2 hosts on this hub sharing the hostname `hub.example.com` under different `HostKey`s, and excluded the unique `host001.example.com`.

`alert.sql`:

```sql
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
```

Paste this into the alert's custom SQL condition editor — it returns `HostKey` (required) plus `HostName` for context, one row per affected host.