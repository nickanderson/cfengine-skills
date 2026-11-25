I verified the query directly against the hub's `/api/query` endpoint (the same reporting DB the Mission Portal alert editor uses) — it correctly flags the two hosts currently reporting the duplicate hostname `hub.example.com` (hostkeys ending `...940` and `...c5`, at `192.168.56.2` and `192.168.56.5`), and excludes the unique `host001.example.com`.

**alert.sql:**
```sql
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
```

The file is written to the working directory, ready to paste into the alert editor.