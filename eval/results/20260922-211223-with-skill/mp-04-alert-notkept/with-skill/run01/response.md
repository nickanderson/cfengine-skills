Both wrapped forms work: the status form returns 1 row (this hub's one failing host), and the host-list form correctly joins to a hostname. Row count equals distinct hostkey count, so it's safe for the alert.

`alert.sql` is written and ready to paste into the Custom SQL alert condition:

```sql
SELECT DISTINCT hostkey
FROM promiseexecutions
WHERE promiseoutcome = 'NOTKEPT'
```

`promiseexecutions` already holds only each host's most recent reported run, and `promiseoutcome` distinguishes `KEPT`/`REPAIRED`/`NOTKEPT`. `DISTINCT` collapses multiple failed promises on one host to a single alerting row, and `hostkey` (required by the alert engine) is returned. Verified against the hub in both the raw status-check form and the wrapped host-list join form Mission Portal actually uses — it currently flags one host.