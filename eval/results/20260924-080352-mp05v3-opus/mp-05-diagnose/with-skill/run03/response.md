I've written `diagnosis.json` to the working directory, and it parses as valid JSON. I queried the hub read-only and changed nothing on it.

```json
{
  "1": {"cause": "agent_not_running", "hostkey": "SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f", "last_agent_run": "2026-09-24T03:36:36+00:00", "last_collected": "2026-09-24T13:10:54+00:00"},
  "2": {"cause": "host_deleted_still_reporting", "hostkey": "SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd", "still_reporting": true, "last_report": "2026-09-24T13:11:53+00:00"},
  "3": {"cause": "hostname_changed", "hostkey": "SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5", "current_hostname": "hub.example.com", "conflicts_with": "SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940"},
  "4": {"cause": "rbac_hidden", "role": "web_team", "class": "debian_12_14"},
  "5": {"cause": "duplicate_hostname", "caused_by": "SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5"}
}
```

1. **host001: the agent isn't running (`agent_not_running`); the hub is collecting fine.** The hub last collected from it at 13:10:54 UTC, along with every other host. The agent's last run was at 03:36:36 UTC, about 9.5 hours earlier, although it normally runs about every 3 minutes. The Health page lists it under "Outdated reporting data". That last run did fail, but the underlying problem is that the agent has stopped running on schedule: the hub keeps collecting the same old data.

2. **host002: yes, it is still reporting (`host_deleted_still_reporting`).** It was deleted in Mission Portal on 2026-09-22 at 22:07 UTC, but its agent is still running and trying to report. Its last attempt was 2026-09-24 at 13:11:53 UTC, which is why the Health page shows it under deleted hosts. To stop the warnings, stop or uninstall the agent on 192.168.56.4.

3. **host003: it's still there under a different name (`hostname_changed`).** The machine at 192.168.56.5 (key `SHA=f20c…`) now reports its hostname as `hub.example.com`. That's the same name the real hub (`SHA=6bb7…`) uses. The oldest name the hub still has on record for it is `hub.example.com`, from 2026-09-24 at 02:46 UTC. Its original name is no longer in that history, so it can't be confirmed there.

4. **Alice: her role's exclusion hides it (`rbac_hidden`).** Alice's only role is `web_team`. That role includes hosts with the `linux` class but excludes anything with `windows|debian_12_14`. host001 has the `debian_12_14` class and no other host does, so her role filters it out.

5. **The hub is fine; the other host is causing it (`duplicate_hostname`).** The Health page lists the hub (192.168.56.2) under "Duplicate hostnames" only because host003 (`SHA=f20c…`) now reports the same name. Fixing host003's hostname clears both entries.

Two other Health entries have nothing to do with these questions:
- **host004:** it has two keys under the same name, a new one and an old record (`SHA=06791f…`) the hub stopped collecting from at 02:43. It looks like the host was given a new key.
- **A synthetic host that was never collected:** its key is `SHA=evaldel1790216183x1`.