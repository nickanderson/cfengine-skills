#!/usr/bin/env python3
"""
Print one line per host currently flagged as unhealthy on the CFEngine
Mission Portal Health page:

    <category>,<hostkey>

Talks to the hub named by $MP_URL, authenticating as $MP_USER / $MP_PASSWORD.
The hub's TLS certificate is expected to be self-signed, so verification is
disabled.

How it works: Mission Portal's Health dropdown is backed by seven SQL
queries (one per health category) that the Angular "reports" app embeds,
already rendered with the current timestamp threshold and the logged-in
username, in the server-rendered health-diagnostic report templates
(/advancedreports/hostDiagnosticView/<name>). This script logs into Mission
Portal to fetch five of those templates (so the exact same live queries MP
itself uses are reused, instead of guessing thresholds), then executes each
query via the hub's /api/query REST endpoint (HTTP Basic auth) and prints
the hostkey found in every returned row.

The other two categories (missing-reporting-data, deleted-hosts-report) are
backed by queries whose outermost FROM target is an internal-only table
(hosts_not_reported / deleted_hosts_report respectively). /api/query refuses
any query where such a table is referenced with a table alias or an inner
WHERE clause ("Query accesses restricted database resources") - the two
report templates trigger that check. The same rows are reachable by scanning
the table bare in a derived subquery (which /api/query does allow) and doing
the filtering in the enclosing query instead, so those two are queried with
an equivalent, hand-rewritten form rather than the template's own SQL.
"""

import base64
import html
import http.cookiejar
import json
import os
import re
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request

# category -> health-diagnostic template name, matching Mission Portal's
# own /reports/health-diagnostic/<category> URLs and dropdown entries.
TEMPLATE_CATEGORIES = [
    ("unreachable-hosts", "notRecentlyCollected"),
    ("outdated-reporting-data", "agentNotRunRecently"),
    ("policy-errors", "lastAgentRunUnsuccessful"),
    ("duplicate-ids", "hostsUsingSameIdentity"),
    ("duplicate-hostnames", "hostsUsingSameName"),
]


def fail(msg):
    print(f"unhealthy-hosts.sh: {msg}", file=sys.stderr)
    sys.exit(1)


def sql_quote(value):
    return value.replace("'", "''")


def run_query(opener, base_url, auth_header, category, sql):
    query_req = urllib.request.Request(
        f"{base_url}/api/query",
        data=json.dumps({"query": sql}).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": auth_header,
            "Content-Type": "application/json",
        },
    )
    try:
        query_resp = opener.open(query_req, timeout=60).read().decode(
            "utf-8", "replace"
        )
    except urllib.error.HTTPError as e:
        fail(
            f"query for {category} failed: HTTP {e.code} "
            f"{e.read().decode('utf-8', 'replace')}"
        )

    try:
        result = json.loads(query_resp)
    except json.JSONDecodeError:
        fail(f"query for {category} returned a non-JSON response: {query_resp!r}")

    result_set = result["data"][0]
    header_names = [col["columnName"] for col in result_set["header"]]
    try:
        key_index = header_names.index("key")
    except ValueError:
        fail(f"query for {category} did not return a 'key' column")

    for row in result_set["rows"]:
        print(f"{category},{row[key_index]}")


def main():
    mp_url = os.environ.get("MP_URL")
    mp_user = os.environ.get("MP_USER")
    mp_password = os.environ.get("MP_PASSWORD")
    if not mp_url or not mp_user or not mp_password:
        fail("MP_URL, MP_USER and MP_PASSWORD must be set")

    base_url = mp_url.rstrip("/")

    ssl_ctx = ssl.create_default_context()
    ssl_ctx.check_hostname = False
    ssl_ctx.verify_mode = ssl.CERT_NONE

    cookiejar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPSHandler(context=ssl_ctx),
        urllib.request.HTTPCookieProcessor(cookiejar),
    )

    # --- Log in to Mission Portal (session cookie needed to read the
    # health-diagnostic report templates, which embed the live SQL). ---
    login_page = opener.open(f"{base_url}/login/index", timeout=30).read().decode(
        "utf-8", "replace"
    )
    m = re.search(r'name="ci_csrf_token"[^>]*value="([^"]+)"', login_page)
    if not m:
        fail("could not find CSRF token on Mission Portal login page")
    csrf_token = m.group(1)

    login_body = urllib.parse.urlencode(
        {
            "ci_csrf_token": csrf_token,
            "username": mp_user,
            "password": mp_password,
            "type_form": "1",
        }
    ).encode("utf-8")

    login_req = urllib.request.Request(
        f"{base_url}/login/index", data=login_body, method="POST"
    )
    login_resp = opener.open(login_req, timeout=30)
    login_resp_body = login_resp.read().decode("utf-8", "replace")
    if "welcome" not in login_resp.headers.get("Refresh", "") and (
        "login" in login_resp_body.lower() and "password" in login_resp_body.lower()
    ):
        fail("Mission Portal login failed; check MP_USER/MP_PASSWORD")

    auth_header = "Basic " + base64.b64encode(
        f"{mp_user}:{mp_password}".encode("utf-8")
    ).decode("ascii")

    # --- Five categories: fetch the live report template (already rendered
    # with the current staleness threshold and the logged-in username baked
    # into its SQL) and run its query as-is. ---
    for category, template in TEMPLATE_CATEGORIES:
        tpl_req = urllib.request.Request(
            f"{base_url}/advancedreports/hostDiagnosticView/{template}"
        )
        try:
            tpl_html = opener.open(tpl_req, timeout=30).read().decode(
                "utf-8", "replace"
            )
        except urllib.error.HTTPError as e:
            fail(f"failed to fetch {template} report template: HTTP {e.code}")

        m = re.search(
            r'<textarea[^>]*id="angularSQLString"[^>]*>(.*?)</textarea>',
            tpl_html,
            re.S,
        )
        if not m:
            fail(f"could not find SQL query for {template} report")
        sql = html.unescape(m.group(1))

        run_query(opener, base_url, auth_header, category, sql)

    # --- The remaining two categories: /api/query rejects the report
    # templates' own SQL outright (it disallows any alias or WHERE clause
    # directly on hosts_not_reported / deleted_hosts_report), so query an
    # equivalent rewritten form: scan the table bare in a derived subquery,
    # then filter/rename in the enclosing query. ---
    user = sql_quote(mp_user)

    run_query(
        opener,
        base_url,
        auth_header,
        "missing-reporting-data",
        "SELECT hostkey as key FROM (SELECT * FROM hosts_not_reported) sub "
        "WHERE hostkey NOT IN (SELECT hostkey FROM health_diagnostics_dismissed "
        f"WHERE username = '{user}' AND report_type = 'hostsNeverCollected')",
    )

    run_query(
        opener,
        base_url,
        auth_header,
        "deleted-hosts-report",
        "SELECT hostkey as key FROM (SELECT * FROM deleted_hosts_report) sub",
    )


if __name__ == "__main__":
    main()
