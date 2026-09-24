`diagnosis.json` written. Summary of findings, all confirmed via the Mission Portal API (`/api/query` against `cfdb` views and `/api/health-diagnostic/*`):

**1. host001 (192.168.56.3) — `agent_not_running`**
`agentstatus` shows `lastagentlocalexecutiontimestamp = 2026-09-24 03:36:36+00`, ~9.5 hours before now, while `hosts.lastreporttimestamp = 2026-09-24 13:10:54+00` — the hub *is* collecting fresh reports right now. So it's not `hub_not_collecting`; the agent itself simply stopped executing on its ~3-minute schedule hours ago (its last recorded run also happened to fail, but that's a stale record, not an ongoing per-run failure). Flagged under Health's "Outdated reporting data" (`agentNotRunRecently`).

**2. host002 (192.168.56.4) — `host_deleted_still_reporting`**
`GET /api/hosts/deleted` and the `deletedHostsReport` health category both show hostkey `SHA=d2224f77...` (192.168.56.4), deleted 2026-09-22 22:07:21+00, with a "Last report attempt" of 2026-09-24 13:13:53+00 — essentially *now*. It was deleted from Mission Portal but its agent (or something using its old key) never stopped reporting.

**3. host003 (192.168.56.5) — `hostname_changed`**
It isn't deleted or gone — the `hosts` view shows its key (`SHA=f20cfa67...`, IP .5) now reporting hostname **"hub.example.com"**, colliding with the real hub's key (`SHA=6bb77202...`, IP .2). Searching Mission Portal for "host003" finds nothing because it renamed itself.

**4. Alice / host001 — `rbac_hidden`**
Alice's only role is `web_team` (`includeContext: linux`, `excludeContext: windows|debian_12_14`). host001's classes include both `linux` and `debian_12_14` — the exclude class wins, so the role's scope filters it out of her host list, even though it's a normal Linux host that shows fine for admin.

**5. Hub (192.168.56.2) on Health page — `duplicate_hostname`, caused by host003**
The hub itself isn't broken — it's flagged because host003 (`SHA=f20cfa67...`) is now also reporting as "hub.example.com" (see #3), so the two keys collide on hostname and both get listed in Health's "Duplicate hostnames" category.

```json
{
  "1": {"cause": "agent_not_running", "hostkey": "SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f", "last_agent_run": "2026-09-24T03:36:36+00:00", "last_collected": "2026-09-24T13:10:54+00:00"},
  "2": {"cause": "host_deleted_still_reporting", "hostkey": "SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd", "still_reporting": true, "last_report": "2026-09-24T13:13:53+00:00"},
  "3": {"cause": "hostname_changed", "hostkey": "SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5", "current_hostname": "hub.example.com", "conflicts_with": "SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940"},
  "4": {"cause": "rbac_hidden", "role": "web_team", "class": "debian_12_14"},
  "5": {"cause": "duplicate_hostname", "caused_by": "SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5"}
}
```

(Note: I also noticed `host004.example.com` shows two hostkeys with a rekey around 02:43–02:44 — a distractor not covered by the five questions, but worth mentioning if you want it investigated too.)