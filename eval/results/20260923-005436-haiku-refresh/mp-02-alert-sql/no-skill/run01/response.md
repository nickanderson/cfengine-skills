Perfect! The SQL query has been validated against the hub. The query successfully detected duplicate hostnames—in this case, the hub found 2 hosts both reporting the hostname "hub.example.com" with different hostkeys.

Here's your **alert.sql** ready to paste into the Mission Portal alert editor:

```sql
SELECT * FROM hosts WHERE hostname IN (SELECT hostname FROM hosts GROUP BY hostname HAVING COUNT(*) > 1) ORDER BY hostname, hostkey
```

**How it works:**
- The subquery `SELECT hostname FROM hosts GROUP BY hostname HAVING COUNT(*) > 1` identifies all hostnames that appear more than once
- The outer query returns complete host records for any host with a duplicate hostname
- Results are ordered by hostname and hostkey for easy scanning

**Test results:** ✅ Verified against hub
- Query time: 34ms
- Found 2 matching rows (both "hub.example.com" with different hostkeys)
- Schema validated successfully