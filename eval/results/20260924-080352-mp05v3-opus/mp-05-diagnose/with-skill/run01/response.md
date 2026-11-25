I wrote the findings to `diagnosis.json`. Everything came from read-only API calls; I changed nothing on the hub. The file validates as JSON.

```json
{
  "1": {"cause": "agent_not_running", "hostkey": "SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f", "last_agent_run": "2026-09-24T03:36:36+00:00", "last_collected": "2026-09-24T13:00:53+00:00"},
  "2": {"cause": "host_deleted_still_reporting", "hostkey": "SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd", "still_reporting": true, "last_report": "2026-09-24T13:04:54+00:00"},
  "3": {"cause": "hostname_changed", "hostkey": "SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5", "current_hostname": "hub.example.com", "conflicts_with": "SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940"},
  "4": {"cause": "rbac_hidden", "role": "web_team", "class": "debian_12_14"},
  "5": {"cause": "duplicate_hostname", "caused_by": "SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5"}
}
```

**1. host001 — the agent isn't running (the hub is collecting fine).** The hub last collected from it at 13:00:53 UTC, which is current. But host001's agent last ran at 03:36:36, about 9.5 hours earlier, and it normally runs about every 3 minutes. So the hub keeps collecting the same old data. The Health page lists host001 under "Outdated reporting data". That last run did end with `FAIL`, but the real problem is that the agent stopped running on schedule, so look at `cf-execd` on host001.

**2. host002 — deleted but still reporting.** It was deleted on 2026-09-22 at 22:07. It is still trying to report, most recently at 13:04:54 today, which is why the Health page lists it under deleted hosts. Its agent is still running, so stop or uninstall the agent on 192.168.56.4. Deleting it again in Mission Portal won't help.

**3. host003 — it now reports under a different hostname.** The machine at 192.168.56.5 now calls itself `hub.example.com`, so it appears in the host list under the hub's name instead of as host003. That name clashes with the real hub (`SHA=6bb772…`).
- **Caveat:** the hub's history has no record of this key ever using the name "host003". The only link is the IP address from your question, so I'm inferring that this key is host003 — I haven't proven it.
- **Fix:** correct the hostname on that machine (for example, in `/etc/hosts` or its hostname setting).

**4. Alice and host001 — hidden by her role.** Alice's only role is `web_team`, which covers hosts with the class `linux` but excludes `windows|debian_12_14`. host001 has `linux`, but it also has `debian_12_14`, and the exclusion wins. That one class is what hides host001 from her.

**5. The hub on the Health page — caused by another host.** The hub is listed under "Duplicate hostnames" only because host003's key (`SHA=f20cfa…`, 192.168.56.5) also reports as `hub.example.com`. Nothing is wrong with the hub itself: it reports normally and its last agent run was OK. Fixing host003's hostname clears this entry.

The same Duplicate hostnames list also shows two keys for `host004.example.com`, both at 192.168.56.6. The older key stopped reporting at 02:43, which looks like host004 was re-keyed. That's outside your five questions, but you may want to clean up the old record.