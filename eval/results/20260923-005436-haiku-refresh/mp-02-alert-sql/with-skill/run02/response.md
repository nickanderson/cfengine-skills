Excellent! Both tests pass. The SQL finds all hosts whose hostname is being reported by multiple hosts. Here's the test summary:

**Raw SQL test** (alert status—triggers when row count > 0):
- Returns 2 rows: two hosts both reporting the hostname `hub.example.com`
- Alert will trigger ✓

**Wrapped SQL test** (how Mission Portal displays the failing hosts):
- Correctly joins the results with the hosts table
- Displays both duplicates with their hostkey and hostname
- Ready for the dashboard ✓

Here's the final alert SQL ready to paste into the Mission Portal alert editor:

```sql
SELECT hostkey, hostname
FROM hosts
WHERE hostname IN (
  SELECT hostname
  FROM hosts
  GROUP BY hostname
  HAVING count(*) > 1
)
ORDER BY hostname, hostkey
```

The SQL is saved in `/tmp/cfeval-mp-02-alert-sql-with-skill.Fs7h61yB/work/alert.sql` and has been verified against your hub.