I wrote the condition to `alert.sql` and tested that exact file against the hub. On your hub right now it matches 2 hosts, the same two that the Health page lists under **Duplicate hostnames**.

```sql
/* Hosts whose hostname is also reported by at least one other host (different hostkey).
   Hostnames are compared case-insensitively; hosts with no hostname are ignored. */
SELECT h.hostkey,
       h.ipaddress AS "IP address",
       h.lastreporttimestamp AS "Last report collected"
FROM hosts h
WHERE COALESCE(h.hostname, '') <> ''
  AND EXISTS (
        SELECT 1
        FROM hosts o
        WHERE lower(o.hostname) = lower(h.hostname)
          AND o.hostkey <> h.hostkey
      )
```

To add it: Dashboard → add alert → condition type **Custom SQL** → paste the file's contents.

**Test results:**
- **Alert status:** I ran the SQL unchanged, the way the alert checks status. It returned 2 rows, one for each host reporting `hub.example.com`:
  - `SHA=f20cfa67…` at 192.168.56.5
  - `SHA=6bb77202…` at 192.168.56.2 (the hub itself)
- **Host list:** I ran it inside the join Mission Portal adds for the alert's host list. It returned the same 2 hosts, with the columns Host name, hostkey, IP address and Last report collected.
- **One row per host:** there were 2 rows and 2 distinct hostkeys, so the alert's failing-host count will be correct.

**Design choices:**
- **Every copy triggers:** each host that shares a hostname is listed, not just one per name, since you asked for every such host.
- **Current state only:** it reads the `hosts` view, which only has each host's current hostname. A host that has been renamed stops triggering the alert.
- **No hostname column:** Mission Portal adds a "Host name" column to the host list itself, so the query doesn't return one; otherwise it would appear twice.
- **Blank hostnames are skipped:** hosts with no hostname are ignored, so they aren't flagged as duplicates of each other.
- **Case is ignored:** `Web01` and `web01` count as the same name, which is stricter than the Health page. To match the Health page exactly, replace `lower(o.hostname) = lower(h.hostname)` with `o.hostname = h.hostname`. On your current data both versions give the same 2 hosts.
- **Paste-ready:** there's no trailing `;` or `--` comment, because Mission Portal wraps the SQL and either would break the query.

The duplicate on your hub looks like another machine (192.168.56.5) reporting the hub's own name, `hub.example.com`. The alert will keep triggering until that machine's hostname is fixed or its record is removed.