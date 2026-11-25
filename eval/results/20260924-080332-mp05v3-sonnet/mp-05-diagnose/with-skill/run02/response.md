Findings, based on live queries against the hub's `/api/query` and `/api/health-diagnostic/` endpoints:

**1. host001 (192.168.56.3)** — `hostkey SHA=73391bc3...d8d8153f`. The hub last **collected** a report at `2026-09-24T13:15:53+00:00` — same cycle as every other live host, so collection is fine. But `agentstatus` shows its last **local agent execution** was `2026-09-24T03:36:36+00:00` (status `FAIL`), nearly 10 hours before the last collection, against a learned run interval of ~184s. The agent has simply stopped running on schedule — the hub isn't the problem. → **agent_not_running**.

**2. host002 (192.168.56.4)** — `hostkey SHA=d2224f77...126387dd`. It's in `deletedHostsReport`, deleted at `2026-09-22T22:07:21+00:00`, but the hub logged a report attempt as recently as `2026-09-24T13:19:54+00:00`. The agent was never stopped/uninstalled after deletion, so it keeps trying to phone home. → **host_deleted_still_reporting**.

**3. host003 (192.168.56.5)** — you won't find "host003" because it renamed itself: the host at `192.168.56.5` (`hostkey SHA=f20cfa67...c799a89c5`) is now reporting under hostname **`hub.example.com`** — identical to the real hub's hostname. It didn't get deleted; it's hiding in the list under the wrong name, and its firstseen timestamp lines up with the real hub's, suggesting a bootstrap/naming mixup. → **hostname_changed**, conflicting with the real hub `SHA=6bb77202...1cae4c940`.

**4. Alice / host001** — Alice's role `web_team` scopes her view with `includeContext: linux`, `excludeContext: windows|debian_12_14`. host001 carries both `linux` and `debian_12_14` classes; the exclude match wins, so it's filtered out of her list even though it matches the include. → **rbac_hidden**, class `debian_12_14`.

**5. Hub (192.168.56.2) flagged on Health page** — the hub itself isn't broken. It shows up under *Duplicate hostnames* purely because host003 (from #3) is now also reporting as `hub.example.com`, colliding with the hub's own identity. → **duplicate_hostname**, caused by `SHA=f20cfa67...c799a89c5` (the renamed host003). Fixing #3 (renaming that host back or re-bootstrapping it) clears this too.

`diagnosis.json` written to the working directory:

```json
{
  "1": {
    "cause": "agent_not_running",
    "hostkey": "SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f",
    "last_agent_run": "2026-09-24T03:36:36+00:00",
    "last_collected": "2026-09-24T13:15:53+00:00"
  },
  "2": {
    "cause": "host_deleted_still_reporting",
    "hostkey": "SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd",
    "still_reporting": true,
    "last_report": "2026-09-24T13:19:54+00:00"
  },
  "3": {
    "cause": "hostname_changed",
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