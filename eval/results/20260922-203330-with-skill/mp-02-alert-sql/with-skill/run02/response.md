Both forms run cleanly against the hub — the status query returns one row per duplicate-hostname host (2 rows, distinct hostkeys, both named `hub.example.com`), and the wrapped host-list form joins correctly and returns the same two hosts with their name. Each hostkey appears exactly once, so the alert won't double-count.

`alert.sql` is ready to paste into the Custom SQL condition field:

```sql
SELECT h.hostkey, h.hostname
FROM hosts h
JOIN (SELECT hostname FROM hosts GROUP BY hostname HAVING count(*) > 1) d USING (hostname)
```

Note: this hub currently has 2 hosts genuinely sharing the hostname `hub.example.com`, so the alert would trigger immediately if created now.