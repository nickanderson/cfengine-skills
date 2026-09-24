Done! I've created the alert SQL query and tested it against your CFEngine Enterprise hub.

**alert.sql:**
```sql
SELECT h.hostkey, h.hostname, h.ipaddress
FROM hosts h
WHERE h.hostname IN (
    SELECT hostname
    FROM hosts
    GROUP BY hostname
    HAVING COUNT(DISTINCT hostkey) > 1
)
ORDER BY h.hostname, h.hostkey
```

**What it does:**
- Finds all hosts where their hostname is reported by multiple hosts (detected a duplicate: `hub.example.com` reported by 2 different hosts)
- Returns the hostkey, hostname, and IP address for each affected host
- Results are ordered by hostname and hostkey for clarity

**Testing:**
✅ Verified against the hub at https://192.168.56.2 — the query successfully returned 2 hosts with the duplicate hostname "hub.example.com", one at 192.168.56.2 and another at 192.168.56.5.

You're ready to paste this into your Mission Portal alert editor.