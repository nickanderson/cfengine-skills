I've written `alert.sql` and run it against the hub. It returns one host right now: the hub, `SHA=6bb77202…c940`.

```sql
SELECT DISTINCT pe.hostkey
FROM promiseexecutions AS pe
JOIN hosts AS h ON h.hostkey = pe.hostkey
WHERE pe.promiseoutcome = 'NOTKEPT'
```

**Why this table:** `promiseexecutions` holds each promise's current outcome, meaning what the host's most recent agent run reported. That's the view you asked for. I didn't use `promiselog` because it's a history table: it has 90 old `NOTKEPT` rows for the hub and would keep alerting on runs that are long over.

**Other choices:**
- **Join to `hosts`:** this leaves out leftover rows from hosts that have been removed from the hub.
- **`DISTINCT hostkey`:** the alert gets exactly one row per host, however many promises failed on it.
- **No trailing semicolon:** Mission Portal may wrap the query inside a larger one, and a semicolon would break that.

**Test results on the hub:**
- The query runs and returns one column, `hostkey`, with one row.
- It also works inside another query (`SELECT count(*) FROM (<query>) AS alert_hosts` → 1).
- The two failing promises on the hub are its `CFEngine Recommendations` method and the `postgresql.conf` files promise. Both are "only warning promised" results from the built-in recommendations policy. So this alert will fire straight away for the hub unless you act on those recommendations or exclude them. For example, you could add `AND pe.bundlename <> 'postgresql_conf_recommendations'`.
- `host001` and the other `hub.example.com` key (`…89c5`) currently have only `KEPT` promises, so they don't match.

I didn't create the alert in Mission Portal itself. You'll need to paste the query into the alert editor's SQL condition.