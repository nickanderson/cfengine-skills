I wrote the alert condition to `alert.sql` and ran it against the hub's query API at `https://192.168.56.2`. It returned the two hosts that should trigger.

```sql
SELECT h.hostkey
FROM hosts h
WHERE COALESCE(TRIM(h.hostname), '') <> ''
  AND EXISTS (
        SELECT 1
        FROM hosts other
        WHERE other.hostkey <> h.hostkey
          AND LOWER(TRIM(other.hostname)) = LOWER(TRIM(h.hostname))
      )
```

**How it works:**
- It returns one `hostkey` per matching host. The custom SQL alert uses that column to decide which hosts trigger.
- A host matches when at least one other host, with a different key, reports the same hostname. Every host in the group triggers, not just one of them.
- Hostnames are compared ignoring case and leading or trailing spaces, since `HUB.example.com` and `hub.example.com` are the same host name.
- Hosts with an empty or missing hostname are left out, so they don't all match each other.

**Result on your hub:** the hub has 5 hosts. The query returned these 2:

| hostkey | hostname | IP |
|---|---|---|
| `SHA=6bb77202…c940` | hub.example.com | 192.168.56.2 |
| `SHA=f20cfa67…89c5` | hub.example.com | 192.168.56.5 |

`host001.example.com`, `decomm01.example.com` and `lab-decomm01.example.com` each have a unique hostname, so they correctly don't match. The second `hub.example.com` at 192.168.56.5 is probably a cloned machine or a reinstall that generated new keys, so it may be worth checking.

I only ran the query; I didn't create the alert in Mission Portal. To set it up, paste the SQL into a custom SQL condition in the dashboard alert editor.