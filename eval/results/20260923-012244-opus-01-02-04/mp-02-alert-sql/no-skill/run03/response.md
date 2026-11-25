I wrote the alert condition to `alert.sql` and ran it against the hub's query API. It returned both hosts that report `hub.example.com` and no others.

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
- It returns a `hostkey` column, which is what the Mission Portal SQL alert condition uses to decide which hosts trigger.
- A host matches only if at least one host with a *different* hostkey reports the same hostname. Each host in a duplicate pair is returned, so both trigger the alert.
- The hostname comparison ignores case and surrounding spaces, since hostnames are case-insensitive. Hosts with a blank or NULL hostname are skipped, so they can't all match each other.
- It uses an exact match, not `LIKE`, so a name that contains another doesn't count. For example, `lab-decomm01.example.com` does not match `decomm01.example.com`.

**Result on the hub (5 hosts):**

| hostkey | hostname | IP | Triggers? |
|---|---|---|---|
| SHA=6bb772…c940 | hub.example.com | 192.168.56.2 | yes |
| SHA=f20cfa…89c5 | hub.example.com | 192.168.56.5 | yes |
| SHA=73391b…153f | host001.example.com | 192.168.56.3 | no |
| SHA=evaldel1 | decomm01.example.com | 0.0.0.1 | no |
| SHA=evaldel2 | lab-decomm01.example.com | 0.0.0.2 | no |

A separate `GROUP BY hostname HAVING count(*) > 1` query found the same single duplicate, `hub.example.com`, reported by 2 hosts.

I checked the query through the query API only. I didn't create the alert in Mission Portal, so paste the query into the alert editor as the condition.