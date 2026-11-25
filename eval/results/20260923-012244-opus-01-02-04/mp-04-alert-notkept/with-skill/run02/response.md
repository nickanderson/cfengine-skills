The alert condition is in `alert.sql`, and I tested the file against your hub. It currently flags 1 host.

**`alert.sql`** (paste into Dashboard → add alert → Custom SQL):

```sql
SELECT hostkey, count(*) AS "Promises not kept"
FROM promiseexecutions
WHERE promiseoutcome = 'NOTKEPT'
GROUP BY hostkey
```

**Why it's built this way:**
- `promiseexecutions` holds only each host's latest reported agent run. Once a host's next run keeps everything, the alert clears for that host. I didn't use the history table (`promiselog`), which would keep flagging hosts that have already recovered.
- `GROUP BY hostkey` gives one row per host. Mission Portal counts rows as failing hosts, so a host with several not-kept promises would otherwise be counted several times.
- The query returns a `hostkey` column, which Mission Portal needs to build the host list. The `Promises not kept` count is extra and shows as a column in that list.
- There's no trailing `;` or `--` comment, because Mission Portal wraps the SQL in its own query and either would break it.

**Check against the hub:**
- **As the alert status runs it** (through `/api/query`), it returned 1 row: `SHA=6bb77202…c940` with 2 not-kept promises.
- **As the host list runs it** (joined to `hosts`), it returned `hub.example.com` with the same hostkey and count.
- **Duplicates:** 1 row and 1 distinct hostkey, so no host is counted twice.
- **Across the hub:** 3 hosts have promise data. 1 host has 2 not-kept promises, and the others show only kept or repaired promises, so the result matches what's there.

**Things to know:**
- "Most recent run" means the most recent run the hub has collected. If a host stops reporting, its last collected results stay in place. For silent hosts, use the Health page's "Unreachable hosts" and "Outdated reporting data" checks.
- The alert sees only the hosts your role allows, and you can narrow it further with the alert's host scope setting.
- Mission Portal has no API for creating alerts, so you'll need to add this one in the dashboard yourself.