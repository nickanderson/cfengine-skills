Excellent! Both tests passed. The SQL correctly identifies all hosts whose hostname is also being reported by a different host. Your hub currently has 2 hosts sharing the hostname "hub.example.com" with different hostkeys.

Here's the ready-to-use alert condition:

**alert.sql:**
```sql
SELECT hostkey, hostname
FROM hosts
WHERE hostname IN (
  SELECT hostname
  FROM hosts
  GROUP BY hostname
  HAVING COUNT(DISTINCT hostkey) > 1
)
```

**How it works:**
- Finds all hostnames reported by multiple distinct hosts
- Returns one row per affected host (required for alert triggering)
- Uses the current-state `hosts` view so the alert reflects live inventory
- The alert triggers whenever any host shares its hostname with another

**To use it:**
Copy the SQL above and paste it into Mission Portal's alert editor as a Custom SQL condition. The alert will fire for every host whose hostname is duplicated, showing the duplicate hostnames in the alert details.