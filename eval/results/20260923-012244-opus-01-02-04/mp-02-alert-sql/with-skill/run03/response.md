I wrote the condition to `alert.sql` and tested it against the hub. It flags 2 hosts, and they are the same 2 that the Health page lists under "Duplicate hostnames".

```sql
/* Hosts whose hostname is also reported by at least one other host (different hostkey).
   Hostnames compared case-insensitively; hosts with no hostname are ignored. */
SELECT h.hostkey,
       h.hostname AS "Reported hostname",
       h.lastreporttimestamp AS "Last report"
FROM hosts AS h
WHERE coalesce(h.hostname, '') <> ''
  AND EXISTS (
        SELECT 1
        FROM hosts AS other
        WHERE lower(other.hostname) = lower(h.hostname)
          AND other.hostkey <> h.hostkey
      )
```

To use it, add an alert on a dashboard, choose the **Custom SQL** condition type and paste the file's contents. There's no API for creating alerts, so this step has to be done in the Mission Portal UI.

**Test results:** I ran the SQL from the file in both of the ways Mission Portal runs an alert condition:
- **Status check (the SQL on its own):** it returned 2 rows. Both hosts report `hub.example.com`: one is the hub itself (`SHA=6bb772…`, 192.168.56.2) and the other is `SHA=f20cfa…` (192.168.56.5).
- **Host list (wrapped and joined back to `hosts`):** it returned the same 2 hosts.

**How the SQL works:**
- **Both hosts are flagged.** It returns every host that shares its name with another host, not just the newer or older one.
- **One row per host.** Mission Portal counts rows as failing hosts, so this matters. The `hosts` view has exactly one row per hostkey (5 rows and 5 distinct keys on this hub), and the query doesn't join anything that could create extra rows.
- **Case doesn't matter.** Hostnames are compared case-insensitively, so `Web01` and `web01` count as duplicates. Hosts with no hostname are skipped, so they don't all match each other.
- **Deleted hosts are ignored.** The query uses the current-state `hosts` view, which leaves out deleted hosts. That matches how the Health page counts duplicate hostnames.
- **Pasting is safe.** There's no trailing `;` or `--` comment, either of which would break it when Mission Portal wraps the SQL. The two extra columns will appear in the alert's host list.

One thing to keep in mind: the reporting views only show hosts the viewing user is allowed to see. If a duplicate is outside that user's access, the alert won't count it.