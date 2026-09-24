Investigated via the Mission Portal API (`/api/host`, `/api/host/<id>/context`, and the `/api/query` SQL reporting endpoint against `Hosts`, `PromiseLog`, `Contexts`, `LastSeenHosts`, `role`/`user`). Findings written to `diagnosis.json`:

**1. host001 (192.168.56.3) — `agent_not_running`**
`Hosts.lastreporttimestamp` for this host is `2026-09-24 13:15:53+00` — essentially "now," proving the hub is reaching and collecting from it fine. But `PromiseLog` and `Contexts` both show only a *single*, non-advancing timestamp: the last actual policy execution was `2026-09-24 03:31:36+00` (outcome: `REPAIRED`, i.e. it succeeded, it just never ran again). The hub keeps polling successfully every ~5 min (`LastSeenHosts` shows the hub's `OUTGOING` connections to it succeeding right up to now), it's just collecting the same stale data because cf-agent/cf-execd stopped running on schedule on the host itself.

**2. host002 (192.168.56.4) — `host_deleted_still_reporting`**
It's absent from the `Hosts` reporting table (consistent with deletion), but `LastSeenHosts` still shows fresh two-way traffic between the hub and hostkey `SHA=d2224f77...` at `192.168.56.4` — an inbound contact at `13:10:32` and the hub's outbound collection attempt succeeding at `13:13:53`, both essentially "now." The host was never un-bootstrapped, so it keeps contacting the hub even though Mission Portal no longer has an inventory record for it — which is exactly what trips the Health page complaint.

**3. host003 (192.168.56.5) — `hostname_changed`**
Its hostkey (`SHA=f20cfa67...`) is alive and well and reporting normally (fresh `LastSeenHosts` entries), but it now reports under hostname **`hub.example.com`** — identical to the real hub's hostname. Searching by "host003" finds nothing because it renamed itself; it collides with the actual hub (`SHA=6bb77202...`).

**4. Alice can't see host001 — `rbac_hidden`**
Alice's user account has role `web_team`, defined as `includeContext: linux`, `excludeContext: windows|debian_12_14`. host001's class list includes both `linux` and `debian_12_14` — the `debian_12_14` exclusion is what hides it from her, even though it also matches the include filter.

**5. Health page lists the hub itself (192.168.56.2) — `duplicate_hostname`, caused by host003**
The hub isn't actually unhealthy — the Health page's duplicate-hostname check flags any hostname shared by two hosts, and since the hub is one half of that pair (the other being host003, `SHA=f20cfa67...`, per #3), the hub shows up on the Health page as a symptom of host003's renamed identity, not a problem with the hub itself.

```json
{
  "1": {"cause": "agent_not_running", "hostkey": "SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f", "last_agent_run": "2026-09-24T03:31:36+00:00", "last_collected": "2026-09-24T13:15:53+00:00"},
  "2": {"cause": "host_deleted_still_reporting", "hostkey": "SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd", "still_reporting": true, "last_report": "2026-09-24T13:13:53+00:00"},
  "3": {"cause": "hostname_changed", "hostkey": "SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5", "current_hostname": "hub.example.com", "conflicts_with": "SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940"},
  "4": {"cause": "rbac_hidden", "role": "web_team", "class": "debian_12_14"},
  "5": {"cause": "duplicate_hostname", "caused_by": "SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5"}
}
```