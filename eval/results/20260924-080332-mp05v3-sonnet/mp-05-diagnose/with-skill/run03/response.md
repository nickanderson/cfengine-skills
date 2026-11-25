I've written `diagnosis.json`. Here are the findings:

```json
{
  "1": {
    "cause": "agent_not_running",
    "hostkey": "SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f",
    "last_agent_run": "2026-09-24T03:36:36+00:00",
    "last_collected": "2026-09-24T13:25:53+00:00"
  },
  "2": {
    "cause": "host_deleted_still_reporting",
    "hostkey": "SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd",
    "still_reporting": true,
    "last_report": "2026-09-24T13:28:53+00:00"
  },
  "3": {
    "cause": "duplicate_hostname",
    "hostkey": "SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5",
    "current_hostname": "hub.example.com",
    "conflicts_with": "SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940"
  },
  "4": {
    "cause": "rbac_hidden",
    "role": "web_team",
    "class": "debian_12_14"
  },
  "5": {
    "cause": "duplicate_hostname",
    "caused_by": "SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5"
  }
}
```

**1. host001 — agent not running, not a collection problem.** The hub last collected a report at 13:25:53 UTC — well within schedule — but `agentstatus.lastagentlocalexecutiontimestamp` shows the agent itself hasn't actually run since 03:36:36 UTC, a ~10-hour gap. The hub is reaching the host fine; cf-agent just stopped executing (cron/service down, not a hub-side or policy failure).

2. **host002 — deleted but still reporting.** It's in `deleted_hosts_report` (deleted 2026-09-22 22:07:21) yet its last report attempt was 2026-09-24 13:28:53 — minutes before this check. Its agent/service was never stopped after the delete, so it keeps trying to report, which is what still flags on the Health page.

3. **host003 — never actually registered under that name; it's a duplicate-hostname collision.** The machine at 192.168.56.5 (hostkey `f20cfa67...`) has reported as `hub.example.com` since its very first report (2026-09-23 12:22:26) — `variableslog` shows only `ADD` entries for `host`/`fqhost`/`uqhost`, never a `CHANGE`, so it didn't rename itself later; it bootstrapped already sharing the real hub's hostname (`6bb77202...`, IP .2, first seen 12:22:26 the same moment). Searching for "host003" finds nothing because no record with that name ever existed — the host is present, just hiding under the hub's name.

4. **Alice can't see host001 — RBAC context exclusion.** Alice's `web_team` role has `includeContext: linux`, `excludeContext: windows|debian_12_14`. host001 has both `linux` and `debian_12_14` classes set; the exclude wins, so the role scope hides it from her specifically (an admin, with no such role, sees it fine).

5. **Hub (192.168.56.2) flagged on Health — caused by host003's collision, not the hub.** The `hostsUsingSameName` report lists both `6bb77202...` (real hub) and `f20cfa67...` (host003, reporting as `hub.example.com`) as a pair sharing the name `hub.example.com`. The hub itself is healthy; it's listed only because another host (`f20cfa67...`) copied its hostname.