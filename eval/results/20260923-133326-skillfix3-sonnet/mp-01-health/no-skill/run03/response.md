Clean stdout, no stderr noise, and the results match what I verified manually against the hub's own health-diagnostic queries. Script written to `unhealthy-hosts.sh`.

How it works: it logs into Mission Portal (form login + CSRF token, since the internal reporting endpoints don't accept the REST API's basic auth), then for each of the 7 panels behind the Health dropdown (Missing reporting data, Deleted hosts still reporting, Unreachable hosts, Outdated reporting data, Policy errors, Duplicate IDs, Duplicate hostnames) it fetches that panel's live SQL query (as rendered for the current user, so it automatically includes that user's dismissed-host exclusions and the hub's configured time thresholds), runs it against the same internal `/advancedreports/results/` endpoint the browser uses, and prints `<category-slug>,<hostkey>` for every returned row.

Current output against the hub:
```
deleted-hosts-report,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
unreachable-hosts,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4
outdated-reporting-data,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
duplicate-hostnames,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5
duplicate-hostnames,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
duplicate-hostnames,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
duplicate-hostnames,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4
```

Full script:

```bash
#!/usr/bin/env bash
#
# Ask a CFEngine Enterprise hub's Mission Portal which hosts its Health page
# currently flags as unhealthy, and print one "<category>,<hostkey>" line per
# flagged host.
#
# The Health page's "flagged host" panels (Missing reporting data, Deleted
# hosts still reporting, Unreachable hosts, Outdated reporting data, Policy
# errors, Duplicate IDs, Duplicate hostnames) are each backed by a SQL query
# against the hub's reporting database. Those queries are not exposed through
# the public /api/query endpoint (they touch internal views/tables that
# endpoint restricts), so this logs into Mission Portal itself, fetches the
# live query used to render each panel for the current user (this also picks
# up that user's dismissed-host exclusions and any configured time
# thresholds), and runs it through the same internal endpoint the Health page
# uses.
#
# Requires: MP_URL, MP_USER, MP_PASSWORD in the environment. curl and jq must
# be installed. The hub's TLS certificate is expected to be self-signed.

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

MP_URL=${MP_URL%/}

COOKIE_JAR=$(mktemp)
trap 'rm -f "$COOKIE_JAR"' EXIT

curl_mp() {
    curl -sk -b "$COOKIE_JAR" -c "$COOKIE_JAR" "$@"
}

# --- Log in to obtain a Mission Portal session cookie ------------------
login_page=$(curl_mp "$MP_URL/login/index")
csrf_token=$(printf '%s' "$login_page" \
    | grep -o 'name="ci_csrf_token" value="[^"]*"' \
    | sed -E 's/.*value="([^"]*)".*/\1/')

if [ -z "$csrf_token" ]; then
    echo "unhealthy-hosts.sh: could not find CSRF token on Mission Portal login page" >&2
    exit 1
fi

curl_mp -o /dev/null \
    --data-urlencode "ci_csrf_token=$csrf_token" \
    --data-urlencode "type_form=login" \
    --data-urlencode "username=$MP_USER" \
    --data-urlencode "password=$MP_PASSWORD" \
    --data-urlencode "timezone=UTC" \
    "$MP_URL/login/index"

welcome=$(curl_mp "$MP_URL/welcome/index")
if printf '%s' "$welcome" | grep -q 'login/index'; then
    echo "unhealthy-hosts.sh: login to Mission Portal failed (check MP_USER/MP_PASSWORD)" >&2
    exit 1
fi

# --- Health page panels: internal report name -> public category slug --
# (slugs match the /reports/health-diagnostic/<slug> links Mission Portal
# itself uses for each panel)
report_types="hostsNeverCollected deletedHostsReport notRecentlyCollected agentNotRunRecently lastAgentRunUnsuccessful hostsUsingSameIdentity hostsUsingSameName"

category_for() {
    case "$1" in
        hostsNeverCollected)       echo "missing-reporting-data" ;;
        deletedHostsReport)        echo "deleted-hosts-report" ;;
        notRecentlyCollected)      echo "unreachable-hosts" ;;
        agentNotRunRecently)       echo "outdated-reporting-data" ;;
        lastAgentRunUnsuccessful)  echo "policy-errors" ;;
        hostsUsingSameIdentity)    echo "duplicate-ids" ;;
        hostsUsingSameName)        echo "duplicate-hostnames" ;;
    esac
}

extract_sql() {
    python3 -c '
import sys, re
html = sys.stdin.read()
m = re.search(r"<textarea[^>]*id=\"angularSQLString\"[^>]*>(.*?)</textarea>", html, re.DOTALL)
sys.stdout.write(m.group(1) if m else "")
'
}

for report_type in $report_types; do
    category=$(category_for "$report_type")

    template=$(curl_mp "$MP_URL/advancedreports/hostDiagnosticView/$report_type")
    sql=$(printf '%s' "$template" | extract_sql)

    if [ -z "$sql" ]; then
        echo "unhealthy-hosts.sh: could not extract query for '$report_type'" >&2
        continue
    fi

    encoded_sql=$(printf '%s' "$sql" | jq -sRr '@uri')

    curl_mp -X POST "$MP_URL/advancedreports/results/" \
        --data-urlencode "SQLString=$encoded_sql" \
        --data-urlencode "sortColumn=" \
        --data-urlencode "sortDescending=0" \
        --data-urlencode "skip=0" \
        --data-urlencode "limit=100000" \
        --data-urlencode "apiUrl=/health-diagnostic/report/$report_type" \
        | jq -r --arg cat "$category" '.rows[]? | select(.[0] != null) | "\($cat),\(.[0])"'
done
```