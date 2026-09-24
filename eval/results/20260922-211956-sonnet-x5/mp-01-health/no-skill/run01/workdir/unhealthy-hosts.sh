#!/usr/bin/env bash
#
# Asks a CFEngine Enterprise hub's Mission Portal which hosts its Health page
# currently flags as unhealthy, and prints one "<category>,<hostkey>" line
# per flagged host on stdout.
#
# Requires MP_URL, MP_USER, MP_PASSWORD in the environment. The hub's
# certificate is expected to be self-signed (curl is run with -k).

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

COOKIE_JAR=$(mktemp)
trap 'rm -f "$COOKIE_JAR"' EXIT

curl_mp() { curl -sk "$@"; }

# --- Log in to get a session (the health-diagnostic queries below need an
# authenticated session, since they touch tables the plain REST /api/query
# endpoint refuses as "restricted database resources"). ---

login_html=$(curl_mp -c "$COOKIE_JAR" "$MP_URL/login/index")
csrf_token=$(printf '%s' "$login_html" | grep -oE 'name="ci_csrf_token" value="[^"]+"' | sed -E 's/.*value="([^"]+)".*/\1/')

curl_mp -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    --data-urlencode "ci_csrf_token=$csrf_token" \
    --data-urlencode "username=$MP_USER" \
    --data-urlencode "password=$MP_PASSWORD" \
    --data-urlencode "type_form=login" \
    -X POST "$MP_URL/login/index" -o /dev/null

if ! grep -q '[[:space:]]cisession[[:space:]]' "$COOKIE_JAR"; then
    echo "unhealthy-hosts.sh: login to $MP_URL failed" >&2
    exit 1
fi

referer="$MP_URL/reports/health-diagnostic"

# Maps each Health-page report type (as used internally by Mission Portal)
# to the category name printed in this script's output. These are exactly
# the report types listed in the Mission Portal Health dropdown.
report_types="notRecentlyCollected lastAgentRunUnsuccessful hostsUsingSameIdentity hostsNeverCollected deletedHostsReport agentNotRunRecently hostsUsingSameName"

category_for() {
    case "$1" in
        notRecentlyCollected)     echo "unreachable-hosts" ;;
        lastAgentRunUnsuccessful) echo "policy-errors" ;;
        hostsUsingSameIdentity)   echo "duplicate-ids" ;;
        hostsNeverCollected)      echo "missing-reporting-data" ;;
        deletedHostsReport)       echo "deleted-hosts-report" ;;
        agentNotRunRecently)      echo "outdated-reporting-data" ;;
        hostsUsingSameName)       echo "duplicate-hostnames" ;;
    esac
}

for report_type in $report_types; do
    category=$(category_for "$report_type")

    # Each health-diagnostic report's page embeds the exact SQL query Mission
    # Portal uses to compute that report (including the current dismissed-host
    # list and time thresholds), in a hidden <textarea sql-ready>. Fetch it
    # fresh so thresholds (e.g. "not reported in the last N minutes") reflect
    # the current time, exactly like the Health page itself does.
    template_html=$(curl_mp -b "$COOKIE_JAR" -e "$referer" \
        "$MP_URL/advancedreports/hostDiagnosticView/$report_type")

    sql=$(printf '%s' "$template_html" | python3 -c '
import re, sys
data = sys.stdin.read()
m = re.search(r"<textarea[^>]*sql-ready[^>]*>(.*?)</textarea>", data, re.S)
print(m.group(1) if m else "")
')

    if [ -z "$sql" ]; then
        echo "unhealthy-hosts.sh: could not extract SQL for report type $report_type" >&2
        continue
    fi

    # Run the report's query the same way the Health page's UI does (its
    # results endpoint permits the restricted tables some categories rely on).
    result=$(curl_mp -b "$COOKIE_JAR" -e "$referer" \
        --data-urlencode "SQLString=$sql" \
        --data-urlencode "sortColumn=" \
        --data-urlencode "sortDescending=0" \
        --data-urlencode "skip=0" \
        --data-urlencode "limit=100000" \
        --data-urlencode "apiUrl=/health-diagnostic/report/$report_type" \
        -X POST "$MP_URL/advancedreports/results/")

    printf '%s' "$result" | python3 -c "
import json, sys
category = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for row in data.get('rows') or []:
    if row and row[0]:
        print(f'{category},{row[0]}')
" "$category"
done
