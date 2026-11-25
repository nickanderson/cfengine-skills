Both forms run cleanly against the hub: the status form returns 4 failing hosts (one row per `hostkey`, no duplicates), and the host-list form correctly joins them to hostnames, showing two hostname pairs (`hub.example.com` x2, `host004.example.com` x2) — exactly the "hostname reported by more than one host" case.

`alert.sql`:

```sql
SELECT hostkey
FROM hosts
WHERE hostname IN (
  SELECT hostname
  FROM hosts
  GROUP BY hostname
  HAVING count(DISTINCT hostkey) > 1
)
```

Paste this into the alert editor's Custom SQL condition field. It returns one `hostkey` row per host whose hostname is shared with at least one other host, using the current-state `hosts` view (so it won't fire for hosts that have since been rekeyed/renamed/deleted).