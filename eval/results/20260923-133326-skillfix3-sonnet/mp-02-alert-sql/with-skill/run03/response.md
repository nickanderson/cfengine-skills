Both forms work: 4 rows, one per hostkey, no trailing `;`/`--`, and each host maps to exactly one hostkey (4 rows, 4 distinct hostkeys) — confirming two pairs of hosts (`host004.example.com` and `hub.example.com`) are each reporting duplicate hostnames.

`alert.sql` is written to the working directory, ready to paste into the Custom SQL alert condition editor:

```sql
SELECT hostkey
FROM hosts h
WHERE EXISTS (
  SELECT 1
  FROM hosts h2
  WHERE h2.hostname = h.hostname
    AND h2.hostkey != h.hostkey
)
```

How it works: for each host in the `hosts` view (one row per hostkey, RBAC-filtered, deleted hosts excluded), it checks whether any *other* host row shares the same `hostname`. Since `hosts` already has one row per hostkey, the result is naturally one row per failing host — no `DISTINCT`/`GROUP BY` needed. Verified against the hub in both the raw form (status check, returns row-count-as-failure-count) and the wrapped host-list form Mission Portal actually uses for the alert's host list.