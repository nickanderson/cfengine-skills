I verified this against the hub's `/api/query` endpoint (the `hosts` table: `hostkey`, `hostname`, `ipaddress`, `lastreporttimestamp`, `firstreporttimestamp`, `hostkeycollisions`). It ran successfully and correctly caught real duplicates already present on your eval hub: `host004.example.com` and `hub.example.com` each report under two distinct hostkeys.

`alert.sql`:

```sql
-- Alert condition: fires for every host whose hostname is also being
-- reported by at least one other host (i.e. the hostname is not unique
-- across distinct hostkeys).
SELECT hostkey, hostname, ipaddress, lastreporttimestamp
FROM hosts
WHERE hostname IN (
  SELECT hostname
  FROM hosts
  GROUP BY hostname
  HAVING COUNT(DISTINCT hostkey) > 1
)
ORDER BY hostname, hostkey
```

The file is at `alert.sql` in the working directory, ready to paste into the Mission Portal alert editor.