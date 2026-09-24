I've written the alert condition to `alert.sql` and tested it on the hub. It flags one host out of three right now: `hub.example.com` itself, which had 2 promises not kept in its latest run.

`alert.sql`:

```sql
SELECT hostkey, count(*) AS "Promises not kept"
FROM promiseexecutions
WHERE promiseoutcome = 'NOTKEPT'
GROUP BY hostkey
```

**How it works:**
- **Only the latest run:** `promiseexecutions` holds just the outcomes from each host's most recent agent run, so a host drops out of the alert as soon as a run finishes with nothing not kept. The history tables would have kept flagging hosts that had since recovered.
- **One row per host:** `GROUP BY hostkey` stops a host with several failed promises from being counted as several failing hosts. The "Promises not kept" column shows up in the alert's host list.
- **Pasteable as-is:** the file has no trailing `;` or `--` comment. Mission Portal wraps the SQL before running it, and either of those would break it.

**Test results:**
- **Alert status check:** I ran the file's exact contents the way Mission Portal checks alert status. It returned 1 row: the hub's key with a count of 2.
- **Host list:** I ran it the way Mission Portal builds the host list (joined to `hosts`). It returned `hub.example.com` with its hostkey and the count of 2.
- **Row count:** the result has 1 row and 1 distinct host, so each host appears once.
- **Cross-check:** grouping all promise outcomes gave 382 kept on 3 hosts, 6 repaired on 1 host and 2 not kept on 1 host. That matches what the alert found.

**To use it:** in Mission Portal, go to Dashboard → add alert and choose a **Custom SQL** condition. Paste in the contents of `alert.sql`, then set the name, severity, host scope and notifications. There's no REST API for creating alerts, so this step has to be done in the UI. I haven't changed anything on the hub.