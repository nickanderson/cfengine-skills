I've written `diagnosis.json` to the working directory, using only read-only API calls. Nothing on the hub was changed.

```json
{
  "1": {"cause": "agent_not_running", "hostkey": "SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f", "last_agent_run": "2026-09-24T03:36:36+00:00", "last_collected": "2026-09-24T13:05:53+00:00"},
  "2": {"cause": "host_deleted_still_reporting", "hostkey": "SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd", "still_reporting": true, "last_report": "2026-09-24T13:07:53+00:00"},
  "3": {"cause": "hostname_changed", "hostkey": "SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5", "current_hostname": "hub.example.com", "conflicts_with": "SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940"},
  "4": {"cause": "rbac_hidden", "role": "web_team", "class": "debian_12_14"},
  "5": {"cause": "duplicate_hostname", "caused_by": "SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5"}
}
```

1. **host001 (192.168.56.3): the agent isn't running, and the hub is collecting fine.** The hub last collected from it at 13:05:53 UTC today, but the agent last ran at 03:36:36 UTC, about 9.5 hours earlier. The data is stale because nothing new is being produced. The Health page lists it under "Outdated reporting data". Its last recorded run is marked `FAIL`, so check the policy once the agent is running again.

2. **host002 (192.168.56.4): deleted, but still reporting.** It was deleted in Mission Portal at 2026-09-22 22:07 UTC. Its agent kept running, and the Health page's "Deleted hosts" report shows its last attempt to report at 2026-09-24 13:07:53 UTC. Stopping or uninstalling the agent on the machine will stop the warning.

3. **host003 (192.168.56.5): now reports as a different hostname.** Nothing named host003 exists in Mission Portal any more. The machine at 192.168.56.5 now reports as `hub.example.com`, which is the hub's own name, so it shows up as a second "hub". The hub still has no record of the name host003, so I couldn't find when the rename happened.

4. **Alice: hidden by her role.** Alice's only role is `web_team`, which includes hosts with class `linux` but excludes `windows|debian_12_14`. host001 has both `linux` and `debian_12_14`, so the `debian_12_14` exclusion hides it. You presumably see it because your role (e.g. admin) has no such exclusion.

5. **The hub (192.168.56.2): nothing is wrong with the hub itself.** It appears under "Duplicate hostnames" because host003 (192.168.56.5, `SHA=f20cfa67…`) also reports `hub.example.com`. Fixing host003's hostname clears the hub's entry.

Two other things the Health page flags, not part of your five questions:
- **host004 (192.168.56.6) was re-keyed.** Its old record (`SHA=06791f18…`) is listed as Unreachable and as a duplicate hostname of the new one.
- **There is a synthetic test record (`SHA=evaldel1790216183x1`)** under "Missing reporting data".