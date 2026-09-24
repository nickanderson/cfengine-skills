I found a cause for all five and wrote them to `diagnosis.json`. The script that re-queries the Mission Portal API and rebuilds that file is `diagnose.py`; it ran cleanly and its output is below. In two of the five cases the writer's own theory was wrong.

### Explanations

1. **host001 — `agent_not_running`.** The hub is collecting from it fine. The last collection was 2026-09-24 13:05:53 UTC, and the hub's own contacts to the host are current. What's stale is the host's agent: its last local run was at **03:36:36 UTC**, about 9.5 hours ago. Its last contact to the hub was around 03:31. The Health page's "agent not run recently" check lists this host. That last run (03:36) also reported `FAIL`, but the main problem is that the agent has stopped running on schedule, so the reports being collected are old.

2. **host002 — `host_deleted_still_reporting`.** Key `SHA=d2224f…87dd` was deleted at 2026-09-22 22:07:21 UTC. It is still trying to report, and the hub still sees its connections in both directions. The last report attempt was **2026-09-24 13:06:53 UTC**. That value will keep moving forward until the agent on the host is stopped or its key is revoked.

3. **host003 — `hostname_changed`.** It didn't disappear. Its key `SHA=f20cfa…89c5` at 192.168.56.5 still reports every 5 minutes, but since about 02:46 UTC today it has reported the hostname **`hub.example.com`**. That now clashes with the real hub, `SHA=6bb772…c940`.

4. **Alice — `rbac_hidden`.** Alice has only the `web_team` role, which includes `linux` and excludes `windows|debian_12_14`. host001 has the class **`debian_12_14`**, so that exclusion hides it from her. The other hosts have `debian_12_9` or `debian_12_15`, so she can still see them.

5. **Hub on the Health page — `duplicate_hostname`.** Nothing is wrong with the hub itself. It appears under "hosts using the same name" because host003's key `SHA=f20cfa…89c5` now reports `hub.example.com` as well (see item 3). Fixing host003's hostname clears it.

There's also a separate duplicate that nobody asked about: two keys at 192.168.56.6 both report `host004.example.com`. It looks like host004 was re-bootstrapped with a new key, and the old key (`SHA=06791f…24c5`) stopped reporting at 02:43 UTC today. Deleting that old entry would clear it from the Health page.

### diagnosis.json
```json
{
  "1": {
    "cause": "agent_not_running",
    "hostkey": "SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f",
    "last_agent_run": "2026-09-24T03:36:36+00:00",
    "last_collected": "2026-09-24T13:05:53+00:00"
  },
  "2": {
    "cause": "host_deleted_still_reporting",
    "hostkey": "SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd",
    "still_reporting": true,
    "last_report": "2026-09-24T13:06:53+00:00"
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

### diagnose.py
```python
#!/usr/bin/env python3
"""Diagnose Mission Portal host issues via the CFEngine Enterprise API; writes diagnosis.json."""
import base64, json, os, ssl, urllib.request
from datetime import datetime, timezone

URL = os.environ["MP_URL"].rstrip("/")
AUTH = base64.b64encode(f'{os.environ["MP_USER"]}:{os.environ["MP_PASSWORD"]}'.encode()).decode()
CTX = ssl._create_unverified_context()  # self-signed cert

def api(path, body=None):
    req = urllib.request.Request(URL + path, method="POST" if body is not None else "GET",
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": "Basic " + AUTH, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, context=CTX) as r:
        return json.load(r)

def rows(res):
    d = res["data"][0]
    cols = [h["columnName"] for h in d["header"]]
    return [dict(zip(cols, r)) for r in d["rows"]]

def sql(q):
    return rows(api("/api/query", {"query": q}))

def report(name):
    return rows(api(f"/api/health-diagnostic/report/{name}", {}))

def iso(ts):
    """'2026-09-24 13:05:53.1+00' -> '2026-09-24T13:05:53+00:00'"""
    dt = datetime.fromisoformat(ts.replace(" ", "T").split(".")[0].split("+")[0]).replace(tzinfo=timezone.utc)
    return dt.isoformat()

hosts = sql("SELECT hostkey, hostname, ipaddress, lastreporttimestamp FROM hosts")
by_ip = lambda ip: [h for h in hosts if h["ipaddress"] == ip]
hub_key = api("/api/")["data"][0]["hub"]["hostkey"]
out = {}

# 1. host001: hub collects fine, but the agent's last local run is hours old.
h1 = by_ip("192.168.56.3")[0]
st = sql(f"SELECT lastagentlocalexecutiontimestamp AS t FROM agentstatus WHERE hostkey='{h1['hostkey']}'")[0]
not_run = {r["key"] for r in report("agentNotRunRecently")}
out["1"] = {"cause": "agent_not_running" if h1["hostkey"] in not_run else "no_problem",
            "hostkey": h1["hostkey"], "last_agent_run": iso(st["t"]),
            "last_collected": iso(h1["lastreporttimestamp"])}

# 2. host002: deleted in MP but still attempting to report.
d = [r for r in report("deletedHostsReport") if r["ipaddress"] == "192.168.56.4"][0]
out["2"] = {"cause": "host_deleted_still_reporting", "hostkey": d["hostkey"],
            "still_reporting": iso(d["Last report attempt"]) > iso(d["Host deleted at"]),
            "last_report": iso(d["Last report attempt"])}

# 3. host003: its key (same IP) now reports a different hostname, clashing with another host.
h3 = by_ip("192.168.56.5")[0]
other = [h for h in hosts if h["hostname"] == h3["hostname"] and h["hostkey"] != h3["hostkey"]][0]
out["3"] = {"cause": "hostname_changed", "hostkey": h3["hostkey"],
            "current_hostname": h3["hostname"], "conflicts_with": other["hostkey"]}

# 4. alice: role excludeContext matches a class on host001.
roles = {r["id"]: r for r in api("/api/role")["data"]}
classes = {r["contextname"] for r in sql(f"SELECT contextname FROM contexts WHERE hostkey='{h1['hostkey']}'")}
for role in api("/api/user/alice")["data"][0]["roles"]:
    for c in roles[role].get("excludeContext", "").split("|"):
        if c in classes:
            out["4"] = {"cause": "rbac_hidden", "role": role, "class": c}

# 5. hub listed on Health page: another key reports the hub's hostname.
dup = [r for r in report("hostsUsingSameName")
       if r["hostname"] == next(h["hostname"] for h in hosts if h["hostkey"] == hub_key) and r["hostkey"] != hub_key]
out["5"] = {"cause": "duplicate_hostname", "caused_by": dup[0]["hostkey"]}

with open("diagnosis.json", "w") as f:
    json.dump(out, f, indent=2)
print(json.dumps(out, indent=2))
```