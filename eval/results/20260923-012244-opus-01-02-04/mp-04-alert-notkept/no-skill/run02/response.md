I've written the alert condition to `alert.sql` and ran it against the hub's query API. It returned one host, as expected.

```sql
SELECT DISTINCT promiseexecutions.hostkey
FROM promiseexecutions
WHERE promiseexecutions.promiseoutcome = 'NOTKEPT'
```

**How it works**
- `promiseexecutions` holds each promise's result from the host's last reported agent run, so this matches "not kept in its most recent run". `promiselog`, by contrast, keeps history, so an old failure that has since been fixed would still set the alert off.
- The alert editor's custom SQL needs a `hostkey` column in the result, one row per host that should trigger. `DISTINCT` stops a host with several failed promises from being listed more than once.

**Result on the hub**
- Promise outcomes on the hub now are 382 kept, 6 repaired and 2 not kept. Both not-kept promises are on the same host.
- The query returns exactly one host: `SHA=6bb77202…4c940` (hub.example.com, 192.168.56.2).
- The two failures there come from the `postgresql_conf_recommendations` files promise and the `CFEngine Recommendations` methods promise that calls it. That promise suggests changes to `postgresql.conf` but is set to only warn, and a warning counts as "not kept". So the alert will fire for this hub straight away unless you exclude that promise.
- The other hosts have no not-kept promises and aren't returned.

**Doesn't cover:** host001.example.com shows `lastagentexecutionstatus = FAIL` in `agentstatus`, and its last agent run was at 2026-09-22 22:37. That's a failed agent run, not a failed promise, so this alert won't catch it. If you want to cover that too, add `UNION SELECT hostkey FROM agentstatus WHERE lastagentexecutionstatus = 'FAIL'`.