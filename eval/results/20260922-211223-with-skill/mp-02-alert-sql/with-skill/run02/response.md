Both forms work as Mission Portal would run them: 2 rows returned (rowCount matches distinct hostkeys — no fan-out), each carrying a `hostkey` column, correctly identifying the two hosts sharing hostname `hub.example.com`.

`alert.sql` is written to the working directory, ready to paste into the alert editor's Custom SQL condition field:

```sql
SELECT h.hostkey, h.hostname AS "Duplicate hostname"
FROM hosts h
WHERE EXISTS (
    SELECT 1 FROM hosts h2
    WHERE h2.hostname = h.hostname
      AND h2.hostkey != h.hostkey
)
```

Notes:
- Uses the `hosts` view (current state, RBAC-filtered, excludes deleted hosts) rather than `__hosts`, so it won't fire on stale/deleted entries.
- One row per `hostkey` naturally (the `hosts` view is one row per host), so no `DISTINCT`/`GROUP BY` needed — verified rowCount (2) equals distinct hostkey count.
- No trailing `;` or `--` comment, so it survives Mission Portal's double-wrapping.
- Verified against the hub in both the raw form (status/count check) and the host-list join form Mission Portal actually executes — both correctly surfaced the two hosts reporting `hub.example.com`.