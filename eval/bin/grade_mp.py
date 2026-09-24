#!/usr/bin/env python3
"""Grade a Mission Portal case against the live hub.

Policy cases are graded by cf-promises; Mission Portal cases have no such
oracle, so the hub is the oracle. The expected answer is re-derived from the
hub's own API at grading time -- never stored in the case -- and the model's
script is run against the same hub to see whether it agrees.

Two entry points:

  grade_mp.py --preflight --case-file C    refuse to start a run on a hub that
                                           is not in the state the case needs
  analyze.py (grader "mission-portal")     calls grade() for one variant

Nothing here is graded by a model. Every check is a set comparison or a
process exit code.
"""

import argparse
import json
import os
import re
import shutil
import signal
import ssl
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from base64 import b64encode
from datetime import datetime, timezone
from pathlib import Path

LINE_RE = re.compile(r"^\s*([^,]+?)\s*,\s*((?:SHA|MD5)=[0-9a-fA-F]+)\s*$")
# A script that reaches around the API has not answered the question the case
# asks, even when its output happens to be right.
OFF_API_RE = re.compile(r"\b(vagrant|psql|cf-hub|ssh)\b|/var/cfengine")

# Health categories go by three names: the report id the API uses, the key in
# /api/health-diagnostic/status (which differs for one of them), and the label
# on the Health page. Any of them is an acceptable <category>.
CATEGORY_ALIASES = {
    "hostsNeverCollected": ["hostsNeverCollected", "Missing reporting data", "never collected"],
    "notRecentlyCollected": ["notRecentlyCollected", "hostNotRecentlyCollected",
                             "Unreachable hosts", "Unreachable host", "not recently collected"],
    "agentNotRunRecently": ["agentNotRunRecently", "Outdated reporting data",
                            "agent not run recently"],
    "lastAgentRunUnsuccessful": ["lastAgentRunUnsuccessful", "Policy errors", "Policy error",
                                 "last agent run unsuccessful"],
    "hostsUsingSameIdentity": ["hostsUsingSameIdentity", "Duplicate IDs", "Duplicate ID"],
    "hostsUsingSameName": ["hostsUsingSameName", "Duplicate hostnames", "Duplicate hostname"],
    "deletedHostsReport": ["deletedHostsReport", "Deleted hosts", "Deleted hosts still reporting"],
}


def _norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


ALIAS_INDEX = {_norm(a): canon for canon, names in CATEGORY_ALIASES.items() for a in names}


def canonical_category(label):
    return ALIAS_INDEX.get(_norm(label))


def api(path, body=None):
    url = os.environ["MP_URL"].rstrip("/") + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method="POST" if data else "GET")
    token = b64encode(("%s:%s" % (os.environ["MP_USER"], os.environ["MP_PASSWORD"])).encode())
    req.add_header("Authorization", "Basic " + token.decode())
    if data:
        req.add_header("Content-Type", "application/json")
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE  # the eval hub's certificate is self-signed
    with urllib.request.urlopen(req, context=ctx, timeout=60) as r:
        return json.loads(r.read())


def expected_health():
    """{(category, hostkey)} as the hub itself reports it."""
    # report_ids is not the full list: on 3.27.1 it omits hostsUsingSameName
    # (the Health page's "Duplicate hostnames"), which /status counts and
    # /report/hostsUsingSameName serves. Take the union.
    ids = list(api("/api/health-diagnostic/report_ids"))
    status = api("/api/health-diagnostic/status")
    ids += [k for k in status if k not in ids and k not in ("total", "totalFailed")]
    pairs = set()
    for rid in ids:
        try:
            table = api("/api/health-diagnostic/report/%s" % rid, {"limit": 10000})["data"][0]
        except urllib.error.HTTPError:
            continue  # a status key with no report of its own
        # Only the first column, "key", is common to every report; "hostkey"
        # is absent from four of the seven.
        col = [h["columnName"] for h in table["header"]].index("key")
        pairs.update((canonical_category(rid) or rid, row[col]) for row in table["rows"])
    return pairs


def query(sql, limit=10000):
    """Run SQL through /api/query -> (header names, rows, error or None)."""
    try:
        table = api("/api/query", {"query": sql, "limit": limit})["data"][0]
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace").strip()
        return [], [], "HTTP %d: %s" % (exc.code, body.splitlines()[0][:200] if body else "")
    return [h["columnName"] for h in table["header"]], table["rows"], None


# How Mission Portal 3.27.1 runs a custom-SQL alert condition, from
# application/modules/dashboard/libraries/CustomAlert.php on the hub:
#  - status: the SQL goes to /api/query unchanged; failing hosts = row count
#  - host list: wrapped as below, joined on a column that must be *named* hostkey
HOST_LIST_WRAP = ('SELECT hosts.HostName AS "Host name",  UserQueryData .* FROM hosts '
                  'INNER JOIN  (%s) AS UserQueryData ON UserQueryData.hostkey = hosts.hostkey')
HISTORY_RE = re.compile(r"\b(?:variables|contexts|software|softwareupdates|promise|promiseexecutions"
                        r"|filechanges|benchmarks)log\b|\b__\w+", re.I)


def alert_truth(case):
    _, rows, err = query(case["expect"]["truth_sql"])
    if err:
        raise RuntimeError("truth query failed: %s" % err)
    return {r[0] for r in rows}


def preflight(case):
    missing = [v for v in case.get("env", []) if not os.environ.get(v)]
    if missing:
        return "unset: %s" % ", ".join(missing)
    if case.get("grader_task") == "stale_records":
        try:
            truth, fresh_dupes, horizon = stale_truth()
        except Exception as exc:  # noqa: BLE001
            return "hub unreachable or API error: %s" % exc
        if not truth:
            return ("no leftover record older than blueHostHorizon (%ds): run lib/mp-rekey-host.sh "
                    "and wait out the horizon" % horizon)
        if case["expect"]["decoy_hostname"] not in fresh_dupes:
            return "decoy gone: %s is not two live records (see lib/mp-setup-hub.sh)" % case["expect"]["decoy_hostname"]
        return None
    if case.get("grader_task") == "host_remove":
        if not os.environ.get("MP_VAGRANT_DIR"):
            return "unset: MP_VAGRANT_DIR (the grader recreates the synthetic hosts)"
        try:
            synthetic(case, "create")
        except Exception as exc:  # noqa: BLE001
            return str(exc)
        _, deleted = hub_hosts()
        if not deleted - {k for k in deleted if k.startswith("SHA=evaldel")}:
            return "no real deleted host to protect (host002; see lib/mp-setup-hub.sh)"
        return None
    if case.get("grader_task") in ("alert_sql", "host_list"):
        try:
            truth = alert_truth(case)
        except Exception as exc:  # noqa: BLE001
            return "hub unreachable or API error: %s" % exc
        need = case["expect"].get("min_truth_hosts", 1)
        if len(truth) < need:
            return ("hub is not in the required state -- %d hosts match, need %d "
                    "(see lib/mp-setup-hub.sh)" % (len(truth), need))
        # A case can depend on a trap in the hub's data (e.g. duplicate rows
        # that make the obvious query overcount). If the data changes and the
        # trap disappears, the case silently gets easier -- refuse instead.
        trap = case["expect"].get("trap_sql")
        if trap:
            _, rows, err = query(trap)
            if err or len(rows) <= len({r[0] for r in rows}):
                return ("the trap this case measures is gone: %r no longer returns more "
                        "rows than hosts (%s)" % (trap, case["expect"].get("trap_note", "")))
        return None
    try:
        truth = expected_health()
    except Exception as exc:  # noqa: BLE001 -- any failure means "do not run"
        return "hub unreachable or API error: %s" % exc
    have = {c for c, _ in truth}
    need = case.get("expect", {}).get("require_categories", [])
    lacking = [c for c in need if c not in have]
    if lacking:
        return ("hub is not in the required state -- no hosts in: %s "
                "(see lib/mp-setup-hub.sh)" % ", ".join(lacking))
    if case.get("grader_task") == "diagnose":
        try:
            t = diagnose_truth(case)
        except Exception as exc:  # noqa: BLE001
            return "hub is not in the required state for mp-05: %s" % exc
        if ("agentNotRunRecently", t["h1"]) not in truth:
            return "host001 is not under agentNotRunRecently (T1)"
        if ("deletedHostsReport", t["h2"]) not in truth:
            return "host002 is not a deleted host still reporting (T2)"
        if t["h3_name"] != t["hub_name"]:
            return "host003 does not share the hub's hostname (T3, T5)"
        if not t["classes"]:
            return "no role of %s excludes a class host001 has (T4)" % case["expect"]["rbac_user"]
    return None


def find_script(workdir, name):
    # Shallowest first, then newest: a draft left in a subdirectory
    # ("attempt1/x.sh") must not win over the script at the top level, and
    # alphabetical order said nothing about which one was final.
    hits = sorted(workdir.rglob(name), key=lambda p: (len(p.relative_to(workdir).parts), -p.stat().st_mtime))
    if hits:
        return hits[0]
    # Accept a differently named script only if it is the sole candidate.
    cands = [p for p in workdir.rglob("*") if p.is_file() and p.suffix in (".sh", ".py")]
    return cands[0] if len(cands) == 1 else None


def run_script(script, timeout=180, args=()):
    tmp = Path(tempfile.mkdtemp(prefix="mpgrade-"))
    try:
        dst = tmp / script.name
        shutil.copy2(script, dst)
        dst.chmod(0o755)
        env = {k: os.environ[k] for k in ("PATH", "HOME", "LANG", "MP_URL", "MP_USER",
                                          "MP_PASSWORD") if k in os.environ}
        # Own process group, killed afterwards: a script that backgrounds a
        # polling loop must not keep acting on the hub after it is graded.
        p = subprocess.Popen([str(dst), *args], cwd=tmp, env=env, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True, start_new_session=True)
        try:
            out, err = p.communicate(timeout=timeout)
            return p.returncode, out, err
        except subprocess.TimeoutExpired:
            return -1, "", "timeout after %ds" % timeout
        finally:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            p.communicate()
    except OSError as exc:
        return -1, "", str(exc)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def grade(case, variant_dir):
    if case.get("grader_task") == "stale_records":
        return grade_stale_records(case, variant_dir)
    if case.get("grader_task") == "host_remove":
        return grade_host_remove(case, variant_dir)
    if case.get("grader_task") == "diagnose":
        return grade_diagnose(case, variant_dir)
    if case.get("grader_task") == "alert_sql":
        return grade_alert_sql(case, variant_dir)
    if case.get("grader_task") == "host_list":
        return grade_host_list(case, variant_dir)
    return grade_health_script(case, variant_dir)


def grade_alert_sql(case, variant_dir):
    w = case["weights"]
    want = case["expect"]["sql_file"]
    workdir = variant_dir / "workdir"
    checks = []

    def add(cid, label, earned, detail):
        checks.append({"id": cid, "label": label, "weight": w[cid],
                       "earned": round(earned, 2), "detail": detail})

    hits = sorted(workdir.rglob(want)) if workdir.exists() else []
    if not hits and workdir.exists():
        sqls = [p for p in workdir.rglob("*.sql") if p.is_file()]
        hits = sqls if len(sqls) == 1 else []
    path = hits[0] if hits else None
    sql = path.read_text(errors="replace").strip() if path else ""
    add("sql_present", "Condition written to %s" % want, w["sql_present"] if sql else 0,
        path.name if path else "not found")

    truth = alert_truth(case)
    cols, rows, err = query(sql) if sql else ([], [], "no SQL")
    add("runs_standalone", "Runs as-is through /api/query (alert status)",
        w["runs_standalone"] if sql and not err else 0, err or "%d rows" % len(rows))

    wcols, wrows, werr = query(HOST_LIST_WRAP % sql) if sql else ([], [], "no SQL")
    add("host_list_wrap", "Survives Mission Portal's host-list wrapper",
        w["host_list_wrap"] if sql and not werr else 0,
        werr or "joins on a hostkey column")

    # Status counts rows, not hosts: duplicate rows inflate "N hosts failing".
    keys = [r[[c.lower() for c in cols].index("hostkey")] for r in rows] \
        if "hostkey" in [c.lower() for c in cols] else []
    distinct = set(keys)
    one_row = bool(rows) and not err and len(rows) == len(distinct)
    add("one_row_per_host", "One row per host (status counts rows)",
        w["one_row_per_host"] if one_row else 0,
        "%d rows, %d distinct hostkeys" % (len(rows), len(distinct)) if keys
        else "no hostkey column" if not err else "did not run")

    got = distinct if keys else set()
    hit = got & truth
    add("hosts_recall", "Every host sharing a hostname triggers",
        w["hosts_recall"] * len(hit) / len(truth) if truth else 0,
        "%d of %d" % (len(hit), len(truth)))
    add("hosts_precision", "No other host triggers",
        w["hosts_precision"] * len(hit) / len(got) if got else 0,
        "%d of %d returned are duplicates" % (len(hit), len(got)))

    hist = sorted(set(m.group(0) for m in HISTORY_RE.finditer(sql)))
    add("current_state", "Uses current-state views, not history or base tables",
        w["current_state"] if sql and not hist else 0,
        "no SQL" if not sql else ("uses: %s" % ", ".join(hist)) if hist else "clean")

    total = round(sum(c["earned"] for c in checks), 1)
    detail = {"script": path.name if path else None, "exit_code": None if err else 0,
              "stdout": sql[:4000], "stderr": err or werr or "",
              "expected": sorted(truth), "got": sorted(got)}
    return checks, total, sum(c["weight"] for c in checks), detail


def api_only_check(script):
    text = script.read_text(errors="replace") if script else ""
    off = sorted(set(m.group(0) for m in OFF_API_RE.finditer(text)))
    uses_api = re.search(r"/api\b", text) is not None
    ok = bool(script) and uses_api and not off
    detail = ("no script" if not script else ("reaches around the API: %s" % ", ".join(off)) if off
              else ("uses /api" if uses_api else "no /api call"))
    return ok, detail


def grade_host_list(case, variant_dir):
    """Every host, not the first page of them: /api/host returns 50 by default."""
    w = case["weights"]
    want = case["expect"]["script"]
    workdir = variant_dir / "workdir"
    checks = []

    def add(cid, label, earned, detail):
        checks.append({"id": cid, "label": label, "weight": w[cid],
                       "earned": round(earned, 2), "detail": detail})

    script = find_script(workdir, want) if workdir.exists() else None
    add("script_present", "Script %s written" % want, w["script_present"] if script else 0,
        script.name if script else "not found")
    rc, out, err = run_script(script) if script else (None, "", "")
    add("runs_clean", "Script exits 0 against the hub", w["runs_clean"] if rc == 0 else 0,
        "rc=%s%s" % (rc, (": " + err.strip().splitlines()[-1][:200]) if rc and err.strip() else ""))

    _, rows, qerr = query(case["expect"]["truth_sql"])
    if qerr:
        raise RuntimeError("truth query failed: %s" % qerr)
    truth = {r[0]: (r[1] or "", r[2] or "") for r in rows}

    lines = [l for l in out.splitlines() if l.strip()]
    got, bad = {}, []
    for l in lines:
        parts = [x.strip().strip('"') for x in l.split(",")]
        if len(parts) != 3 or not re.match(r"^(SHA|MD5)=\w+$", parts[0]):
            bad.append(l)
            continue
        got[parts[0]] = (parts[1], parts[2])
    ok_frac = (len(lines) - len(bad)) / len(lines) if lines else 0
    add("output_parses", "Every line is <hostkey>,<hostname>,<ip>", w["output_parses"] * ok_frac,
        "%d/%d lines parse%s" % (len(lines) - len(bad), len(lines),
                                 ("; first bad: %r" % bad[0][:120]) if bad else ""))

    hit = set(got) & set(truth)
    add("hosts_recall", "Every host listed",
        w["hosts_recall"] * len(hit) / len(truth) if truth else 0,
        "%d of %d hosts" % (len(hit), len(truth)))
    # The prompt says it must not miss any host: a feed missing one host is as
    # wrong for a CMDB as one missing a thousand, so this half is all-or-nothing.
    add("complete", "No host missing (all or nothing)",
        w["complete"] if truth and len(hit) == len(truth) else 0,
        "complete" if truth and len(hit) == len(truth) else "%d missing" % (len(truth) - len(hit)))
    add("hosts_precision", "Only real, current hosts listed",
        w["hosts_precision"] * len(hit) / len(got) if got else 0,
        "%d of %d listed are current hosts" % (len(hit), len(got)))
    right = sum(1 for k in hit if got[k] == truth[k])
    add("fields_correct", "Hostname and IP match the hub",
        w["fields_correct"] * right / len(hit) if hit else 0,
        "%d of %d listed hosts" % (right, len(hit)))
    ok, detail = api_only_check(script)
    add("api_only", "Answers through the REST API only", w["api_only"] if ok else 0, detail)

    total = round(sum(c["earned"] for c in checks), 1)
    detail = {"script": script.name if script else None, "exit_code": rc,
              "stdout": out[-2000:], "stderr": err[-2000:],
              # 1122 keys is too much to store per run; the counts carry the result.
              "expected": ["%d hosts" % len(truth)], "got": ["%d hosts" % len(got)]}
    return checks, total, sum(c["weight"] for c in checks), detail


def grade_health_script(case, variant_dir):
    w = case["weights"]
    want = case.get("expect", {}).get("script", "")
    workdir = variant_dir / "workdir"
    checks = []

    def add(cid, label, earned, detail):
        checks.append({"id": cid, "label": label, "weight": w[cid],
                       "earned": round(earned, 2), "detail": detail})

    script = find_script(workdir, want) if workdir.exists() else None
    add("script_present", "Script %s written" % want, w["script_present"] if script else 0,
        script.name if script else "not found")

    rc, out, err = run_script(script) if script else (None, "", "")
    add("runs_clean", "Script exits 0 against the hub",
        w["runs_clean"] if rc == 0 else 0,
        "rc=%s%s" % (rc, (": " + err.strip().splitlines()[-1][:200]) if rc and err.strip() else ""))

    # Truth is taken after the script runs: the script only reads, and the
    # hub's state is what it was asked about at the moment it answered.
    truth = expected_health()
    truth_keys = {k for _, k in truth}

    lines = [l for l in out.splitlines() if l.strip()]
    parsed, bad = set(), []
    unknown_cats = set()
    for l in lines:
        m = LINE_RE.match(l)
        if not m:
            bad.append(l)
            continue
        canon = canonical_category(m.group(1))
        if canon is None:
            unknown_cats.add(m.group(1))
        parsed.add((canon or m.group(1), m.group(2)))
    ok_frac = (len(lines) - len(bad)) / len(lines) if lines else 0
    add("output_parses", "Every stdout line is <category>,<hostkey>",
        w["output_parses"] * ok_frac,
        "%d/%d lines parse%s" % (len(lines) - len(bad), len(lines),
                                 ("; first bad: %r" % bad[0][:120]) if bad else ""))

    got_keys = {k for _, k in parsed}
    hit = got_keys & truth_keys
    add("hosts_recall", "Every flagged host listed",
        w["hosts_recall"] * len(hit) / len(truth_keys) if truth_keys else 0,
        "%d of %d flagged hosts" % (len(hit), len(truth_keys)))
    add("hosts_precision", "No healthy host listed",
        w["hosts_precision"] * len(hit) / len(got_keys) if got_keys else 0,
        "%d of %d listed are flagged" % (len(hit), len(got_keys)))

    # Per host, not per (category, host) pair. The Health page's counts put a
    # host in one category, but the report lists can overlap: on 3.27.1 a
    # re-keyed host's stale record is in both "Unreachable hosts" and
    # "Duplicate hostnames". Any of a host's categories is right.
    truth_cats, got_cats = {}, {}
    for c, k in truth:
        truth_cats.setdefault(k, set()).add(c)
    for c, k in parsed:
        got_cats.setdefault(k, set()).add(c)
    right = sum(1 for k, cs in truth_cats.items() if got_cats.get(k, set()) & cs)
    add("categories_correct", "Each host under the right category",
        w["categories_correct"] * right / len(truth_cats) if truth_cats else 0,
        "%d of %d flagged hosts under one of their categories%s" % (
            right, len(truth_cats),
            ("; unrecognised categories: %s" % ", ".join(sorted(unknown_cats))) if unknown_cats else ""))

    text = script.read_text(errors="replace") if script else ""
    off = sorted(set(m.group(0) for m in OFF_API_RE.finditer(text)))
    # "/api" not "/api/": scripts commonly build the base as "$MP_URL/api".
    # The UI's own endpoints (/advancedreports/..., /login/index) do not count --
    # they need a session cookie and CSRF token and are not a supported API.
    uses_api = re.search(r"/api\b", text) is not None
    add("api_only", "Answers through the REST API only",
        w["api_only"] if script and uses_api and not off else 0,
        "no script" if not script else ("reaches around the API: %s" % ", ".join(off)) if off
        else ("uses /api" if uses_api else "no /api call"))

    total = round(sum(c["earned"] for c in checks), 1)
    detail = {
        "script": script.name if script else None,
        "exit_code": rc,
        "stdout": out[-4000:],
        "stderr": err[-2000:],
        "expected": sorted("%s,%s" % p for p in truth),
        "got": sorted("%s,%s" % p for p in parsed),
    }
    return checks, total, sum(c["weight"] for c in checks), detail


def parse_ts(value):
    """ISO 8601 or PostgreSQL timestamp -> aware datetime; None if unparseable or
    without a UTC offset (the prompt asks for one: a bare time is ambiguous)."""
    if not isinstance(value, str) or not value.strip():
        return None
    v = value.strip().replace("Z", "+00:00")
    v = re.sub(r"([+-]\d\d)$", r"\1:00", v)          # PostgreSQL "+00"
    v = re.sub(r"(\.\d{6})\d+", r"\1", v)
    try:
        d = datetime.fromisoformat(v)
    except ValueError:
        return None
    return d if d.tzinfo else None


def diagnose_truth(case):
    """The answer to each numbered mp-05 item, from the hub as it is now."""
    exp = case["expect"]
    ips = exp["ips"]
    _, rows, err = query("SELECT h.hostkey, h.hostname, h.ipaddress, h.lastreporttimestamp, "
                         "a.lastagentlocalexecutiontimestamp FROM hosts h "
                         "LEFT JOIN agentstatus a USING (hostkey)")
    if err:
        raise RuntimeError(err)
    by_ip = {}
    for r in rows:
        by_ip.setdefault(r[2], []).append(r)
    for name in ("host001", "host003", "hub"):
        if len(by_ip.get(ips[name], [])) != 1:
            raise RuntimeError("expected one live host at %s (%s)" % (ips[name], name))
    h1, h3, hub = (by_ip[ips[n]][0] for n in ("host001", "host003", "hub"))

    deleted = api("/api/hosts/deleted")["data"]
    h2 = next((d["hostkey"] for d in deleted if d.get("ipaddress") == ips["host002"]), None)
    if not h2:
        raise RuntimeError("host002 (%s) is not a deleted host" % ips["host002"])
    rep = api("/api/health-diagnostic/report/deletedHostsReport", {"limit": 10000})["data"][0]
    cols = [h["columnName"] for h in rep["header"]]
    row = next((r for r in rep["rows"] if r[0] == h2), None)
    last_attempt = row[cols.index("Last report attempt")] if row else None

    # T4: the classes in an excludeContext of the user's roles that host001 has.
    _, crow, err = query("SELECT contextname FROM contexts WHERE hostkey = '%s'" % h1[0])
    h1_classes = {c[0].lower() for c in crow}
    roles, classes = set(), set()
    for rid in api("/api/user/%s" % exp["rbac_user"])["data"][0].get("roles", []):
        role = api("/api/role/%s" % rid)["data"][0]
        hit = {t.lower() for t in re.split(r"[|.,&!() ]+", role.get("excludeContext") or "") if t} & h1_classes
        if hit:
            roles.add(rid.lower())
            classes |= hit
    return {"h1": h1[0], "h1_last_agent_run": h1[4], "h1_last_collected": h1[3],
            "h2": h2, "h2_last_report": last_attempt,
            "h3": h3[0], "h3_name": h3[1], "hub": hub[0], "hub_name": hub[1],
            "roles": roles, "classes": classes}


def grade_diagnose(case, variant_dir):
    w = case["weights"]
    tol = case["expect"]["tolerance_s"]
    workdir = variant_dir / "workdir"
    checks = []

    def add(cid, label, ok, detail, frac=None):
        label = re.sub(r"^T(\d):", r"#\1:", label)  # items are numbered; check ids keep t1_...
        earned = w[cid] * (frac if frac is not None else (1 if ok else 0))
        checks.append({"id": cid, "label": label, "weight": w[cid],
                       "earned": round(earned, 2), "detail": detail})

    want = case["expect"]["file"]
    hits = sorted(workdir.rglob(want)) if workdir.exists() else []
    if not hits and workdir.exists():
        js = [p for p in workdir.rglob("*.json") if p.is_file()]
        hits = js if len(js) == 1 else []
    text = hits[0].read_text(errors="replace") if hits else ""
    try:
        ans = json.loads(text) if text else {}
        if not isinstance(ans, dict):
            ans = {}
    except ValueError:
        ans = {}
    add("file_parses", "%s written and parses" % want, bool(ans),
        "parses" if ans else ("not found" if not text else "invalid JSON"))

    t = diagnose_truth(case)
    now = datetime.now(timezone.utc)

    def field(tid, key):
        # Items are numbered "1".."5" in the prompt; rubric 1-2 answers used "T1".."T5".
        item = ans.get(tid[1:]) if isinstance(ans.get(tid[1:]), dict) else ans.get(tid)
        v = item.get(key) if isinstance(item, dict) else None
        return v.strip() if isinstance(v, str) else v

    def same_key(tid, key, truth):
        v = field(tid, key)
        return isinstance(v, str) and v.lower() == (truth or "").lower(), v or "missing"

    def cause(tid, expected):
        v = field(tid, "cause")
        ok = isinstance(v, str) and v.lower() == expected
        add("%s_cause" % tid.lower(), "%s: cause is %s" % (tid, expected), ok, v or "missing")

    def when(cid, label, tid, key, truth, moving):
        got, want_ = parse_ts(field(tid, key)), parse_ts(truth)
        if want_ is None:
            raise RuntimeError("no truth for %s" % cid)
        if got is None:
            return add(cid, label, False, "%r: not an ISO timestamp with an offset" % field(tid, key))
        diff = (got - want_).total_seconds()
        if moving:  # the hub keeps updating it: accept a recent reading, not a future one
            ok = -tol["moving_before"] <= diff <= tol["moving_after"] and got <= now
        else:
            ok = abs(diff) <= tol["static"]
        add(cid, label, ok, "%s vs %s (%+ds)" % (got.isoformat(), want_.isoformat(), diff))

    cause("T1", "agent_not_running")
    ok, v = same_key("T1", "hostkey", t["h1"])
    add("t1_hostkey", "T1: host001's hostkey", ok, v)
    when("t1_last_agent_run", "T1: last agent run", "T1", "last_agent_run", t["h1_last_agent_run"], False)
    when("t1_last_collected", "T1: last collection (recent: the hub is collecting)", "T1",
         "last_collected", t["h1_last_collected"], True)

    cause("T2", "host_deleted_still_reporting")
    ok, v = same_key("T2", "hostkey", t["h2"])
    add("t2_hostkey", "T2: host002's hostkey", ok, v)
    sr = field("T2", "still_reporting")
    add("t2_still_reporting", "T2: still reporting", sr is True, repr(sr))
    # /api/hosts/deleted keeps the last report *before deletion*; the host is
    # still trying, which only the health report's "Last report attempt" shows.
    when("t2_last_report", "T2: last report attempt (now, not at deletion)", "T2", "last_report",
         t["h2_last_report"], True)

    cause("T3", "hostname_changed")
    ok, v = same_key("T3", "hostkey", t["h3"])
    add("t3_hostkey", "T3: host003's hostkey", ok, v)
    ok, v = same_key("T3", "current_hostname", t["h3_name"])
    add("t3_current_hostname", "T3: its hostname now (%s)" % t["h3_name"], ok, v)
    ok, v = same_key("T3", "conflicts_with", t["hub"])
    add("t3_conflicts_with", "T3: collides with the hub's hostkey", ok, v)

    cause("T4", "rbac_hidden")
    role = field("T4", "role")
    add("t4_role", "T4: role %s" % ", ".join(sorted(t["roles"])),
        isinstance(role, str) and role.lower() in t["roles"], role or "missing")
    cls = field("T4", "class")
    cls_l = cls.lower() if isinstance(cls, str) else ""
    exact = cls_l in t["classes"]
    # The whole exclude expression names the setting but not the class that matched.
    partial = not exact and any(c in re.split(r"[|.,&!() ]+", cls_l) for c in t["classes"])
    add("t4_class", "T4: the class host001 has (%s)" % ", ".join(sorted(t["classes"])),
        exact, cls or "missing", frac=1 if exact else 0.5 if partial else 0)

    cause("T5", "duplicate_hostname")
    ok, v = same_key("T5", "caused_by", t["h3"])
    add("t5_caused_by", "T5: caused by host003", ok, v)

    total = round(sum(c["earned"] for c in checks), 1)
    expected = ["#1 agent_not_running", "#2 host_deleted_still_reporting", "#3 hostname_changed",
                "#4 rbac_hidden %s" % ",".join(sorted(t["classes"])), "#5 duplicate_hostname"]
    got = ["#%s %s" % (k[1:], field(k, "cause")) for k in ("T1", "T2", "T3", "T4", "T5")]
    detail = {"script": hits[0].name if hits else None, "exit_code": 0 if ans else None,
              "stdout": text[:4000], "stderr": "", "expected": expected, "got": got}
    return checks, total, sum(c["weight"] for c in checks), detail


def hub_hosts():
    """({live hostkey: hostname}, {deleted hostkey})"""
    live = {h["id"]: h.get("hostname") for h in api("/api/host?count=1000")["data"]}
    deleted = {h["hostkey"] for h in api("/api/hosts/deleted?limit=1000")["data"]}
    return live, deleted


def synthetic(case, action):
    """Run the case's synthetic-host helper (create|cleanup)."""
    helper = Path(__file__).resolve().parent.parent / case["expect"]["helper"]
    p = subprocess.run(["bash", str(helper), action], capture_output=True, text=True, timeout=300)
    if p.returncode != 0:
        raise RuntimeError("%s %s failed: %s" % (helper.name, action, (p.stderr or p.stdout).strip()[-300:]))


def grade_host_remove(case, variant_dir):
    """Run the model's removal script against a freshly made target and decoy.

    The hub's own answers are the traps: DELETE /api/host/:key returns 202 for
    any key, existing or not; permanent deletion of a live host is a 404; and
    the path in older docs (/api/host/delete-permanently/...) is taken as a
    regular delete of a host named "delete-permanently" -- 202 again, nothing
    removed. Only the resulting state counts.
    """
    w = case["weights"]
    exp = case["expect"]
    workdir = variant_dir / "workdir"
    checks = []

    def add(cid, label, ok, detail):
        checks.append({"id": cid, "label": label, "weight": w[cid],
                       "earned": w[cid] if ok else 0, "detail": detail})

    script = find_script(workdir, exp["script"]) if workdir.exists() else None
    add("script_present", "Script %s written" % exp["script"], bool(script),
        script.name if script else "not found")

    synthetic(case, "create")
    live0, deleted0 = hub_hosts()
    target = next((k for k, n in live0.items() if n == exp["target"]), None)
    decoy = next((k for k, n in live0.items() if n == exp["decoy"]), None)
    if not target or not decoy:
        raise RuntimeError("target or decoy missing after create")
    others_live = {k for k in live0 if k not in (target, decoy)}

    rc, out, err = run_script(script, timeout=300, args=(exp["target"],)) if script else (None, "", "")
    add("runs_clean", "Exits 0 removing %s" % exp["target"], rc == 0,
        "rc=%s%s" % (rc, (": " + err.strip().splitlines()[-1][:200]) if rc and err.strip() else ""))
    live1, deleted1 = hub_hosts()

    add("target_not_live", "Target gone from the host list", target not in live1,
        "gone" if target not in live1 else "still live")
    add("target_purged", "Target gone from deleted hosts too (permanently deleted)",
        target not in live1 and target not in deleted1,
        "purged" if target not in live1 and target not in deleted1
        else "still in /api/hosts/deleted" if target in deleted1 else "still live")
    add("decoy_untouched", "%s untouched" % exp["decoy"], decoy in live1 and decoy not in deleted1,
        "live" if decoy in live1 else ("deleted" if decoy in deleted1 else "purged"))
    lost_live = sorted(others_live - set(live1))
    lost_deleted = sorted(deleted0 - deleted1 - {target})
    add("others_untouched", "No other host deleted or purged (host002 stays in deleted hosts)",
        not lost_live and not lost_deleted,
        "ok" if not lost_live and not lost_deleted
        else "removed: %s" % ", ".join(k[:14] for k in lost_live + lost_deleted))

    # Run again: the host no longer exists, and the script must say so.
    rc2, out2, err2 = run_script(script, timeout=120, args=(exp["target"],)) if script else (None, "", "")
    live2, deleted2 = hub_hosts()
    add("missing_host_fails", "Rerun for a host that is gone exits 1 and changes nothing",
        rc2 == 1 and set(live2) == set(live1) and deleted2 == deleted1,
        "rc=%s" % rc2)

    ok, detail = api_only_check(script)
    add("api_only", "Answers through the REST API only", ok, detail)

    synthetic(case, "cleanup")
    total = round(sum(c["earned"] for c in checks), 1)
    detail = {"script": script.name if script else None, "exit_code": rc,
              "stdout": (out + "\n--- rerun ---\n" + out2)[-4000:], "stderr": (err + err2)[-2000:],
              "expected": ["remove %s" % target, "keep %s" % decoy] + ["keep deleted %s" % k[:14] for k in sorted(deleted0)],
              "got": ["live: %s" % " ".join(sorted(k[:14] for k in live1)),
                      "deleted: %s" % " ".join(sorted(k[:14] for k in deleted1))]}
    return checks, total, sum(c["weight"] for c in checks), detail


def stale_truth():
    """{stale hostkey: (current hostkey, hostname, ip)} and the horizon.

    A leftover record shares its hostname with a record that is reporting
    (last report within blueHostHorizon) while it is not. Two records that
    are both reporting -- two live machines with one name -- are not.
    """
    horizon = api("/api/settings")["data"][0]["blueHostHorizon"]  # seconds (3.27.1)
    _, rows, err = query("SELECT hostkey, hostname, ipaddress, "
                         "extract(epoch FROM lastreporttimestamp) FROM hosts")
    if err:
        raise RuntimeError(err)
    now = datetime.now(timezone.utc).timestamp()
    groups = {}
    for key, name, ip, ts in rows:
        if name:
            groups.setdefault(name, []).append((key, ip, float(ts or 0)))
    stale, fresh_dupes = {}, {}
    for name, recs in groups.items():
        if len(recs) < 2:
            continue
        fresh = [r for r in recs if now - r[2] <= horizon]
        old = [r for r in recs if now - r[2] > horizon]
        if len(fresh) >= 2:
            fresh_dupes[name] = [r[0] for r in fresh]
        if fresh and old:
            cur = max(fresh, key=lambda r: r[2])
            for r in old:
                stale[r[0]] = (cur[0], name, r[1])
    return stale, fresh_dupes, horizon


def grade_stale_records(case, variant_dir):
    w = case["weights"]
    exp = case["expect"]
    workdir = variant_dir / "workdir"
    checks = []

    def add(cid, label, frac, detail):
        checks.append({"id": cid, "label": label, "weight": w[cid],
                       "earned": round(w[cid] * frac, 2), "detail": detail})

    script = find_script(workdir, exp["script"]) if workdir.exists() else None
    add("script_present", "Script %s written" % exp["script"], 1 if script else 0,
        script.name if script else "not found")
    rc, out, err = run_script(script) if script else (None, "", "")
    add("runs_clean", "Script exits 0 against the hub", 1 if rc == 0 else 0,
        "rc=%s%s" % (rc, (": " + err.strip().splitlines()[-1][:200]) if rc and err.strip() else ""))

    truth, fresh_dupes, horizon = stale_truth()
    lines = [l for l in out.splitlines() if l.strip()]
    got, bad = {}, []
    for l in lines:
        p = [x.strip().strip('"') for x in l.split(",")]
        if len(p) != 4 or not all(re.match(r"^(SHA|MD5)=\w+$", x) for x in p[:2]):
            bad.append(l)
            continue
        got[p[0]] = p[1]
    add("output_parses", "Every line is <stale>,<current>,<hostname>,<ip>",
        (len(lines) - len(bad)) / len(lines) if lines else 0,
        "%d/%d lines parse%s" % (len(lines) - len(bad), len(lines),
                                 ("; first bad: %r" % bad[0][:120]) if bad else ""))
    hit = set(got) & set(truth)
    add("stale_recall", "Every leftover record found", len(hit) / len(truth) if truth else 0,
        "%d of %d" % (len(hit), len(truth)))
    live_flagged = sorted(k for k in got if k not in truth)
    # All or nothing: the next step is deleting these records, and one live
    # record on the list is a live machine removed from Mission Portal.
    add("no_live_listed", "No live record listed as leftover (%s is two live machines)"
        % exp["decoy_hostname"], 1 if got and not live_flagged else 0,
        ("wrongly listed: %s" % ", ".join(k[:14] for k in live_flagged)) if live_flagged
        else ("none listed" if not got else "ok"))
    right = sum(1 for k in hit if got[k] == truth[k][0])
    add("current_correct", "Current record named correctly", right / len(truth) if truth else 0,
        "%d of %d" % (right, len(truth)))
    ok, detail = api_only_check(script)
    add("api_only", "Answers through the REST API only", 1 if ok else 0, detail)

    total = round(sum(c["earned"] for c in checks), 1)
    detail = {"script": script.name if script else None, "exit_code": rc,
              "stdout": out[-4000:], "stderr": err[-2000:],
              "expected": sorted("%s,%s" % (k, v[0]) for k, v in truth.items()),
              "got": sorted("%s,%s" % kv for kv in got.items())}
    return checks, total, sum(c["weight"] for c in checks), detail


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preflight", action="store_true")
    ap.add_argument("--case-file", required=True)
    args = ap.parse_args()
    case = json.loads(Path(args.case_file).read_text())
    if args.preflight:
        problem = preflight(case)
        if problem:
            sys.exit("grade_mp: %s: %s" % (case["id"], problem))
        print("grade_mp: %s: hub ready" % case["id"])


if __name__ == "__main__":
    main()
