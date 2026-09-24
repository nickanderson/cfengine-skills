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
