Both forms work: the raw condition returns one row per failing host with a `hostkey` column, and the host-list wrapper joins cleanly and resolves the hostname. One host (`hub.example.com`) currently has 2 not-kept promises in its most recent run.

**alert.sql:**
```sql
SELECT hostkey, COUNT(*) AS "Not kept promises"
FROM promiseexecutions
WHERE promiseoutcome = 'NOTKEPT'
GROUP BY hostkey
```

This uses `promiseexecutions`, the current-state view holding each host's most recent run outcomes (not the history log), so it won't fire for hosts that have since recovered. It's grouped by `hostkey` so each failing host produces exactly one row, satisfying Mission Portal's custom-SQL alert requirements. Paste it into Dashboard → Add alert → Custom SQL condition.