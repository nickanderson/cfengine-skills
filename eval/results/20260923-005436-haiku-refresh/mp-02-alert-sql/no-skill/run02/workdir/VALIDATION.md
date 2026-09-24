# Alert SQL Validation Report

## Query Purpose
Detects all hosts in CFEngine Enterprise that are reporting a hostname already being reported by a different host. This identifies potential:
- Misconfigured hostnames
- Clone/duplicate systems
- Hostname conflicts

## SQL Query
```sql
SELECT h.hostkey
FROM hosts h
WHERE h.hostname IN (
    SELECT hostname
    FROM hosts
    GROUP BY hostname
    HAVING COUNT(DISTINCT hostkey) > 1
)
ORDER BY h.hostname, h.hostkey
```

## Query Logic
1. **Inner Subquery**: Groups all hosts by hostname and counts distinct hostkeys
   - Identifies hostnames reported by more than 1 unique host
2. **Outer Query**: Selects all hostkeys matching those duplicate hostnames
3. **Result**: Returns the `hostkey` of every host involved in a hostname conflict

## Example
Given these hosts in the Mission Portal:
```
hostkey          hostname
-----------      ---------------------
host_ubuntu01    webserver.example.com
host_ubuntu02    webserver.example.com   ← DUPLICATE
host_centos01    appserver.example.com
host_debian01    appserver.example.com   ← DUPLICATE
host_fedora01    unique.example.com
```

The alert query returns:
```
hostkey
-----------
host_ubuntu01    ← has duplicate hostname
host_ubuntu02    ← has duplicate hostname  
host_centos01    ← has duplicate hostname
host_debian01    ← has duplicate hostname
```

(host_fedora01 is NOT returned because its hostname is unique)

## SQL Validation
✓ Valid PostgreSQL syntax
✓ Uses standard HAVING clause for GROUP aggregation
✓ Proper JOIN/subquery structure
✓ Returns results ordered by hostname then hostkey
✓ Compatible with CFEngine's "hosts" table schema

## How to Use in Mission Portal
1. Open Mission Portal Alert Editor
2. Create new alert or edit existing one
3. In the "Condition" field, paste the SQL from `alert.sql`
4. Set trigger name: "Duplicate Hostname Detected"
5. Configure email/notification recipients as needed
