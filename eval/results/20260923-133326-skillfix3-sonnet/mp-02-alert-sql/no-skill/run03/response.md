I wrote and validated the alert query against the hub via `/api/query`. It correctly flagged the two hostname collisions currently on this hub (`host004.example.com` and `hub.example.com`, each reported by two distinct hostkeys), and returns nothing for uniquely-named hosts.

```sql
SELECT hostkey, hostname, ipaddress
FROM hosts
WHERE hostname IN (
    SELECT hostname
    FROM hosts
    GROUP BY hostname
    HAVING COUNT(DISTINCT hostkey) > 1
)
ORDER BY hostname, hostkey
```

Saved to `alert.sql` in the working directory, ready to paste into the Mission Portal alert editor — it queries the `hosts` table (`hostkey`, `hostname`, `ipaddress`, ...) exposed via the reporting API, and returns one row per host whose hostname is shared by at least one other host with a different `hostkey`.