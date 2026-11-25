The alert condition is in `alert.sql` and works on your hub. Right now it flags 2 hosts: both report the hostname `hub.example.com`, from 192.168.56.2 and 192.168.56.5.

```sql
/* Hosts whose hostname is also reported by at least one other host (different hostkey).
   Hostnames are compared case-insensitively; hosts with no hostname are ignored. */
SELECT h.hostkey,
       h.ipaddress AS "IP address",
       h.lastreporttimestamp AS "Last report collected",
       (SELECT count(*) FROM hosts o
         WHERE lower(o.hostname) = lower(h.hostname)
           AND o.hostkey <> h.hostkey) AS "Other hosts with this name"
FROM hosts h
WHERE coalesce(h.hostname, '') <> ''
  AND EXISTS (SELECT 1 FROM hosts o
               WHERE lower(o.hostname) = lower(h.hostname)
                 AND o.hostkey <> h.hostkey)
```

**Using it:** there's no API for creating alerts, so you add it in the UI: Dashboard → add alert → condition type **Custom SQL** → paste the contents of `alert.sql` → choose severity, host scope and notifications.

**What I checked on the hub (3.27.1), using the exact text in the file:**
- **Alert status:** the query returns 2 rows. Mission Portal counts rows as failing hosts, so the alert triggers.
- **One row per host:** there are 2 rows and 2 distinct hostkeys, so no host is counted twice.
- **Host list:** I wrapped the query the way Mission Portal does for the alert's host list. It returns both hosts, with the "Host name" column filled in.
- **Health page:** the Health page's "Duplicate hostnames" list shows the same 2 hosts.

**Why it's written this way:**
- It reads the current `hosts` view, not the base tables. So deleted hosts are left out, and a host drops off the alert as soon as its hostname changes.
- It returns the `hostkey` column that the alert needs, with no trailing `;` or `--` comment, since Mission Portal wraps the query and either would break it.
- Hostnames are compared ignoring case, so `Web01` and `web01` count as the same name. The Health page compares them exactly. If you want to match that, remove the `lower()` calls.
- Hosts that report no hostname are skipped, so they don't all show up as duplicates of each other.
- The extra columns (IP address, last report time, and how many other hosts share the name) appear in the alert's host list to help you tell the duplicates apart.