Both forms work correctly against the hub: the status query returns 2 rows (one per hostkey, no duplicates), and the wrapped host-list query correctly resolves both hostkeys to hostname `hub.example.com` — confirming this pair genuinely shares a hostname. Rows equal distinct hostkeys, so the alert will report the correct failing-host count.

The file `alert.sql` is ready to paste into the alert editor as a Custom SQL condition:

```sql
SELECT DISTINCT hostkey
FROM hosts
WHERE hostname IN (
    SELECT hostname
    FROM hosts
    GROUP BY hostname
    HAVING COUNT(*) > 1
)
```

This returns one `hostkey` row per host whose hostname is shared with at least one other host, using the current-state `hosts` view (so it won't fire for hosts that have since stopped reporting or changed hostname).