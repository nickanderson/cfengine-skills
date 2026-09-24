Perfect! ✓ Both tests pass. Your alert condition is ready.

**What it does:** Detects all hosts whose hostname is also reported by a different host. The hub has 4 such hosts: two reporting as `host004.example.com` and two reporting as `hub.example.com`, each pair with different hostkeys.

**File:** `/tmp/cfeval-mp-02-alert-sql-with-skill.Y9dpPfCk/work/alert.sql`

```sql
SELECT DISTINCT h.hostkey
FROM hosts h
WHERE h.hostname IN (
  SELECT hostname
  FROM hosts
  GROUP BY hostname
  HAVING count(*) > 1
)
```

To use it:
1. In Mission Portal, go to Dashboard → add alert
2. Set **Condition type** to **Custom SQL**
3. Paste the SQL above into the **Condition** field
4. Set your severity, host scope, and notifications

The query has been validated:
- ✓ Direct form: returns 4 failing hosts (status check)
- ✓ Wrapped form: correctly joins with hostname display for the alert's host list