Both forms work: the bare query returns one row per duplicate host (`hostkey`, `hostname`), and the Mission Portal host-list wrapping correctly joins it to `hosts.HostName`. On this hub it correctly found the 2 hosts both reporting `hub.example.com`.

`alert.sql` is ready to paste into the alert editor's Custom SQL condition field:

```sql
SELECT h.hostkey, h.hostname
FROM hosts h
JOIN (SELECT hostname FROM hosts GROUP BY hostname HAVING count(*) > 1) d USING (hostname)
```

Notes for setup in the Mission Portal alert editor:
- Condition type: **Custom SQL**
- Status = number of rows returned; each returned row already deduplicates by `hostkey`, so counts will match hosts (not pairs) 1:1.
- No trailing `;` or `--` comment — Mission Portal wraps this SQL twice, and either would break it (confirmed this by testing the exact wrapped form above).
- Uses the current-state `hosts` view, so it only flags hosts currently reporting a duplicated hostname, not ones that shared one historically.