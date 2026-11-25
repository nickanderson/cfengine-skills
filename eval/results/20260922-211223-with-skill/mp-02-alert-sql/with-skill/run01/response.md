Both forms work as Mission Portal will run them: 2 rows returned (rowCount = distinct hostkeys, no fan-out), correctly flagging the two `hub.example.com` hosts, and the host-list join resolves properly. `alert.sql` is written and ready to paste into the alert editor's Custom SQL condition.

```sql
SELECT hostkey, hostname AS "Duplicate hostname"
FROM hosts
WHERE hostname IN (
  SELECT hostname
  FROM hosts
  GROUP BY hostname
  HAVING count(*) > 1
)
```

Notes:
- Returns one row per failing `hostkey` (required by the alert host-list join), no duplicates.
- Uses the `hosts` view (current state, RBAC-filtered, excludes deleted hosts) rather than `__hosts`.
- No trailing `;` or `--` comment, since Mission Portal wraps the SQL twice.
- Validated live: the lab hub already has two hosts both named `hub.example.com`, and both the raw status query and the fully-wrapped host-list query returned exactly those two rows.