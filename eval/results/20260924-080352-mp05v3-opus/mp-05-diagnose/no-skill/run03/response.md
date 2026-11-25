I've written the findings to `diagnosis.json`. `investigate.sh` re-runs the API queries I used. The API was queried on 2026-09-24 at about 13:10 UTC. In three of the five cases the writer's own theory was wrong.

### 1. host001 — `agent_not_running` (the hub is collecting fine)
- **Hostkey:** `SHA=73391bc3…153f`
- **Why:** The hub collected from host001 at **2026-09-24 13:05:53 UTC**, in the same cycle as every other host. Collection is not the problem. But `agentstatus` shows the agent's last local run was at **03:36:36 UTC**, even though its run interval is about 3 minutes. So the hub keeps collecting the same old data because the agent has stopped running. The Health page lists it under "agent not run recently".
- **Note:** that last run is marked `FAIL`. I still chose `agent_not_running` over `policy_failing` because the main fault is that the agent has made no runs at all for more than 9 hours.

### 2. host002 — `host_deleted_still_reporting` (yes, it still reports)
- **Hostkey:** `SHA=d2224f77…87dd`
- **Why:** The deleted-hosts report shows it was deleted at 2026-09-22 22:07:21 UTC. Its last report attempt was **2026-09-24 13:09:55 UTC**, only seconds before I checked. The hub's lastseen table also shows host002 (192.168.56.4) still connecting every 5 minutes.
- **Fix:** it will keep appearing until you stop its agent, or revoke its key on the hub.

### 3. host003 — `hostname_changed`
- **Hostkey:** `SHA=f20cfa67…89c5`
- **Where it went:** The host at 192.168.56.5 is still reporting normally, but it now calls itself **`hub.example.com`** (`fqhost=hub.example.com`, `uqhost=hub`). No host called host003 exists any more.
- **Conflicts with:** the real hub, `SHA=6bb77202…c940` (192.168.56.2).
- **Not a shared key:** the two hosts have different hostkeys and zero key collisions, so this is not `duplicate_identity`.

### 4. Alice — `rbac_hidden`
- **Role:** alice's only role is **`web_team`**, which includes `linux` hosts but excludes `windows|debian_12_14`.
- **Class:** host001 is the only host with the class **`debian_12_14`**, so that exclude rule hides it from her. You can see it because your role doesn't have that rule.

### 5. The hub on the Health page — `duplicate_hostname` (nothing is wrong with the hub itself)
- **Why:** The hub is listed under "hosts using the same name", together with the host from item 3 (192.168.56.5), which now also reports as `hub.example.com`. The hub's own collection and agent runs are healthy.
- **Caused by:** `SHA=f20cfa67…89c5`. Correcting that host's hostname clears both this item and item 3.

**Other things the Health page shows** (not part of the five questions):
- host004 (192.168.56.6) appears twice. The old key `SHA=06791f18…` stopped reporting at 02:43 UTC, which suggests the host was re-bootstrapped with a new key.
- A test entry, `SHA=evaldel1790216183x1`, is listed as never collected.

**diagnosis.json**
```json
{
  "1": {"cause": "agent_not_running", "hostkey": "SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f", "last_agent_run": "2026-09-24T03:36:36+00:00", "last_collected": "2026-09-24T13:05:53+00:00"},
  "2": {"cause": "host_deleted_still_reporting", "hostkey": "SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd", "still_reporting": true, "last_report": "2026-09-24T13:09:55+00:00"},
  "3": {"cause": "hostname_changed", "hostkey": "SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5", "current_hostname": "hub.example.com", "conflicts_with": "SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940"},
  "4": {"cause": "rbac_hidden", "role": "web_team", "class": "debian_12_14"},
  "5": {"cause": "duplicate_hostname", "caused_by": "SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5"}
}
```

**investigate.sh**
```bash
#!/bin/bash
# Re-runs the Mission Portal API queries used to build diagnosis.json.
# Needs MP_URL, MP_USER, MP_PASSWORD. -k because the hub cert is self-signed.
A=(-sk -u "$MP_USER:$MP_PASSWORD")
q() { curl "${A[@]}" -X POST -H 'Content-Type: application/json' "$MP_URL/api/query" -d "{\"query\":\"$1\"}"; echo; }

echo "### Health diagnostics summary"
curl "${A[@]}" "$MP_URL/api/health-diagnostic/status"; echo
for r in deletedHostsReport hostsNeverCollected notRecentlyCollected hostsUsingSameName hostsUsingSameIdentity agentNotRunRecently lastAgentRunUnsuccessful; do
  echo "### Health report: $r"
  curl "${A[@]}" -X POST -H 'Content-Type: application/json' "$MP_URL/api/health-diagnostic/report/$r" -d '{}'; echo
done

echo "### Hosts"
q "SELECT hostkey,hostname,ipaddress,lastreporttimestamp,firstreporttimestamp,hostkeycollisions FROM hosts"
echo "### Agent status"
q "SELECT * FROM agentstatus"
echo "### Hostname variables"
q "SELECT hostkey,variablename,variablevalue FROM variables WHERE variablename IN ('fqhost','uqhost')"
echo "### Hub lastseen (incoming connections from hosts)"
q "SELECT remotehostkey,remotehostip,lastseendirection,lastseentimestamp FROM lastseenhosts WHERE hostkey='SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940'"

echo "### RBAC: alice and her role"
curl "${A[@]}" "$MP_URL/api/user/alice"; echo
curl "${A[@]}" "$MP_URL/api/role/web_team"; echo
q "SELECT hostkey,contextname FROM contexts WHERE contextname IN ('linux','windows','debian_12_14')"
```