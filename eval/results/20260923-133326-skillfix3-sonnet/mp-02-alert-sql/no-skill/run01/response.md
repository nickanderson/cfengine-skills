I verified this by running it against the hub's live report database through the Mission Portal query API (using `$MP_URL`/`$MP_USER`/`$MP_PASSWORD`). It ran cleanly against the `hosts` view (`hostkey`, `hostname`, `ipaddress`, ...) and correctly flagged 4 of the 5 known hosts as duplicates:

- `host004.example.com` reported by two different hostkeys (192.168.56.6 twice)
- `hub.example.com` reported by two different hostkeys (192.168.56.2 and 192.168.56.5)

The `EXISTS` self-join compares each host's hostname against every other host, matching on hostname but excluding the host itself via `hostkey <>`, so a hostname is flagged only when at least one *different* host reports it. Using plain `=` (rather than a NULL-safe comparison) also naturally excludes hosts with an unknown/NULL hostname from ever matching each other.

```sql
SELECT h.hostkey, h.hostname, h.ipaddress
FROM hosts h
WHERE EXISTS (
    SELECT 1
    FROM hosts h2
    WHERE h2.hostname = h.hostname
      AND h2.hostkey <> h.hostkey
)
ORDER BY h.hostname, h.hostkey;
```

Saved to `alert.sql` in the working directory — ready to paste into the alert editor.