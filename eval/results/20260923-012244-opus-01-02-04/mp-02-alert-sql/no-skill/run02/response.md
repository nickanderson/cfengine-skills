I wrote `alert.sql` and ran it against the hub at `https://192.168.56.2` through `/api/query`. It returns the two hosts that both report `hub.example.com`, and no others.

**`alert.sql`**
```sql
SELECT h.hostkey AS hostkey
FROM hosts h
WHERE NULLIF(TRIM(h.hostname), '') IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM hosts other
    WHERE other.hostkey <> h.hostkey
      AND LOWER(TRIM(other.hostname)) = LOWER(TRIM(h.hostname))
  )
```

**What it does:**
- **Which hosts:** it returns every host whose hostname is also reported by a host with a different host key. Every host in a duplicate pair or group triggers the alert, not just one of them.
- **Output:** it returns a single `hostkey` column. My understanding is that the alert editor's custom SQL condition expects that, and that each returned host counts as failing. I didn't confirm this in the editor itself.
- **No trailing semicolon:** I left it off in case Mission Portal wraps the query in a subquery. I checked that wrapping it as `SELECT hostkey FROM (…) t` works on this hub.
- **Hostname matching:** names are compared ignoring case and leading or trailing spaces, so `Hub.example.com` and `hub.example.com ` count as the same. Hosts with an empty or missing hostname are left out, so they don't all match each other.
- **Exact names only:** hosts with similar but different names aren't matched, such as `decomm01.example.com` and `lab-decomm01.example.com`.

**Results on the hub right now (5 hosts):**

| hostkey | hostname | IP |
|---|---|---|
| `SHA=f20cfa67…89c5` | hub.example.com | 192.168.56.5 |
| `SHA=6bb77202…c940` | hub.example.com | 192.168.56.2 |

`host001`, `decomm01` and `lab-decomm01` aren't returned, which is correct.

The query uses the `hosts.hostname` column, which is the hostname Mission Portal shows. On this hub it matches each host's `sys.fqhost`. I didn't create an alert on the hub to test it, so paste it into the alert editor to set one up.