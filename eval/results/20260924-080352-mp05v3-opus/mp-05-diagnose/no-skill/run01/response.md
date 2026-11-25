I've checked all five issues through the Mission Portal API (host list, Health diagnostic reports, SQL queries on `hosts`, `agentstatus`, `variables` and `contexts`, and the users and roles endpoints). In three cases the writer's theory was wrong. The findings are in `diagnosis.json`, which parses as valid JSON.

**1. host001 – `agent_not_running`**
The hub is collecting from host001 fine: the last collection was 2026-09-24 13:00:53 UTC, the same as every other host. The agent itself last ran at 03:36:36 UTC, about 9.5 hours earlier. Health lists it under "agent not run recently", so the hub keeps collecting the same old data. The "last agent run unsuccessful" report is empty, so it isn't a policy failure.

**2. host002 – `host_deleted_still_reporting`**
The host (SHA=d2224f…) was deleted at 2026-09-22 22:07:21 UTC. It is still reporting: the hub recorded a report attempt from 192.168.56.4 at 2026-09-24 13:03:54 UTC. That's why Health's "deleted hosts" report still lists it.

**3. host003 – `hostname_changed`**
The host at 192.168.56.5 (SHA=f20cfa…) is still reporting normally. Its hostname is now `hub.example.com` (fqhost `hub.example.com`, uqhost `hub`), so searching for "host003" finds nothing. That name clashes with the real hub (SHA=6bb772…). The host key is its own, and the key-collision count is 0.

**4. Alice – `rbac_hidden`**
Alice has only the role `web_team`. That role includes hosts with the `linux` class but excludes `windows|debian_12_14`. host001 has the class `debian_12_14`, so the exclude rule hides it from her.

**5. Hub on the Health page – `duplicate_hostname`**
Nothing is wrong with the hub itself: its agent ran at 12:58:55 and it was collected at 13:00:53. It appears under "hosts using same name" because host003 (SHA=f20cfa…) now also reports as `hub.example.com`.

Health also shows two issues nobody asked about. Two host keys both report as `host004.example.com` at 192.168.56.6; the old key (06791f…) hasn't reported since 02:43, which looks like host004 was re-keyed. There's also an entry never collected from, `SHA=evaldel1790216183x1` at 0.0.0.1, which looks like leftover test data.

The timestamp in answer 2 is truncated to whole seconds (the API gives 13:03:54.596554).

Files are in the working directory:
- `diagnosis.json`

```json
{
  "1": {"cause": "agent_not_running", "hostkey": "SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f", "last_agent_run": "2026-09-24T03:36:36+00:00", "last_collected": "2026-09-24T13:00:53+00:00"},
  "2": {"cause": "host_deleted_still_reporting", "hostkey": "SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd", "still_reporting": true, "last_report": "2026-09-24T13:03:54+00:00"},
  "3": {"cause": "hostname_changed", "hostkey": "SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5", "current_hostname": "hub.example.com", "conflicts_with": "SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940"},
  "4": {"cause": "rbac_hidden", "role": "web_team", "class": "debian_12_14"},
  "5": {"cause": "duplicate_hostname", "caused_by": "SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5"}
}
```