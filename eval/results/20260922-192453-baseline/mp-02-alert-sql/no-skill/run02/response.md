I checked the hub's `hosts` reporting view (`hostkey`, `hostname`, `ipaddress`, ...) and confirmed via `$MP_URL/api/query` that this query correctly flags exactly the hosts sharing a duplicate hostname on your hub — two hostkeys both reporting `hub.example.com` — while excluding the unique `host001.example.com`.

`alert.sql`:

```sql
-- Mission Portal alert condition:
-- Triggers for every host whose hostname is also reported by a different
-- host (i.e. two or more distinct host keys sharing the same hostname).
SELECT
    h.hostkey,
    h.hostname,
    h.ipaddress
FROM hosts h
WHERE EXISTS (
    SELECT 1
    FROM hosts h2
    WHERE h2.hostname = h.hostname
      AND h2.hostkey <> h.hostkey
)
ORDER BY h.hostname;
```

Ready to paste into the alert editor's condition field.