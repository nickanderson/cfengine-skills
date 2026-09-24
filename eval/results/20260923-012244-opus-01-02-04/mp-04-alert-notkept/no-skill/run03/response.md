I wrote the alert condition to `alert.sql` and ran it against the hub. It returns one host, `hub.example.com` (`SHA=6bb77202…c940`).

```sql
SELECT DISTINCT hostkey
FROM PromiseExecutions
WHERE promiseoutcome = 'NOTKEPT'
```

**Why this table:** `PromiseExecutions` holds only the latest outcome of each promise on each host. Filtering it on `NOTKEPT` therefore means "a promise was not kept in the host's most recent run." `PromiseLog` wouldn't work for this, because it keeps every past run and would keep alerting on failures that have since been fixed. The alert only needs to return `hostkey`.

**What I checked on the hub:**
- The query runs through `/api/query`. I also ran it as a subquery joined to `Hosts`, which is roughly how the alert editor will use it. Both gave the same single host.
- For that host, the two `NOTKEPT` promises come from the `postgresql.conf` recommendations bundle. That bundle is set to warn only, so it's reported as not kept even though nothing actually broke. `PromiseLog` shows `NOTKEPT` for it at 06:33:52, which is exactly the host's last agent run.
- Two things the query does not catch:
  - **Duplicate hostname:** another host is also named `hub.example.com` (`SHA=f20cfa67…`). All its promises are kept, so it isn't in the result.
  - **Failed agent run:** `host001.example.com` has `lastagentexecutionstatus = FAIL` and hasn't run since 2026-09-22 22:37. When the agent run itself fails, no promise outcomes come back, so this alert won't flag it. If you want that covered, add a second alert on `AgentStatus.lastagentexecutionstatus = 'FAIL'`.

**Files** (in the working directory):
- `alert.sql`: the condition above.
- `q.sh`: a small helper I used to send the queries to `/api/query`:

```bash
#!/bin/bash
curl -sk -u "$MP_USER:$MP_PASSWORD" -H 'Content-Type: application/json' -X POST "$MP_URL/api/query" -d "$(jq -n --arg q "$1" '{query:$q}')"
```