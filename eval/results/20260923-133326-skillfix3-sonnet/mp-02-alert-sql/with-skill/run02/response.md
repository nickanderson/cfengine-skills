Confirmed: 4 rows, 4 distinct hostkeys, each paired with a hostname shared by exactly one other host (`hub.example.com` and `host004.example.com` each appear twice). Both the Status form and the host-list form work correctly, with no trailing `;` and no trailing `--` comment.

`alert.sql`:

```sql
SELECT hostkey
FROM hosts
WHERE hostname IN (
  SELECT hostname
  FROM hosts
  GROUP BY hostname
  HAVING count(*) > 1
)
```

This uses the `hosts` view (current state, RBAC-filtered, one row per host), returns the required `hostkey` column, and naturally yields one row per failing host — so no `DISTINCT`/`GROUP BY hostkey` wrapper was needed. Paste it directly into the Custom SQL condition field when creating the alert.