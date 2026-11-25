Both forms work correctly against the live hub: the plain query returns one row per duplicate-hostname host (found 2 real hosts both reporting `hub.example.com`), and the wrapped host-list form joins cleanly, confirming the `hostkey` column matches as required by the alert UI.

`alert.sql`:

```sql
SELECT h.hostkey, h.hostname
FROM hosts h
JOIN (SELECT hostname FROM hosts GROUP BY hostname HAVING count(*) > 1) d USING (hostname)
```

Paste this directly into the Custom SQL condition field of a new dashboard alert. It returns one row per host (via `hostkey`) whenever that host's hostname is also reported by at least one other distinct host — verified live against the hub, where it correctly flagged the two hosts currently sharing `hub.example.com`.