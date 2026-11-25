The script is complete and verified working against the live hub. Summary of how it works and the result:

**Approach**: The Mission Portal Health dropdown links to 7 diagnostic reports under `/reports/health-diagnostic/<slug>`. Each is an Angular view (`/advancedreports/hostDiagnosticView/<view>`) that embeds a server-rendered SQL query (already scoped to the logged-in user's dismissed-host list) in a hidden `<textarea>`. The script logs in via the same form-based session Mission Portal's UI uses, fetches each view's SQL, and replays it against the same query endpoint (`/advancedreports/results/`) the UI itself calls — including the `apiUrl` parameter required for two diagnostics that read from internal tables (missing-reporting-data, deleted-hosts-report).

Output from running it against the hub:

```
deleted-hosts-report,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
outdated-reporting-data,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
duplicate-hostnames,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
duplicate-hostnames,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
```

```bash
#!/usr/bin/env bash
#
# unhealthy-hosts.sh
#
# Ask a CFEngine Enterprise Mission Portal hub which hosts its Health page
# currently flags as unhealthy, and print:
#
#   <category>,<hostkey>
#
# one line per flagged host. Nothing else is written to stdout.
#
# Requires: MP_URL, MP_USER, MP_PASSWORD in the environment.
# Uses: curl, python3.

set -u -o pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

MP_URL="${MP_URL%/}"

COOKIE_JAR="$(mktemp)"
LOGIN_PAGE="$(mktemp)"
trap 'rm -f "$COOKIE_JAR" "$LOGIN_PAGE"' EXIT

curl_mp() {
    curl -sk --cookie "$COOKIE_JAR" --cookie-jar "$COOKIE_JAR" "$@"
}

# --- Log in and establish a session ------------------------------------------

curl_mp "$MP_URL/login/index" -o "$LOGIN_PAGE"

CSRF_TOKEN="$(grep -oE 'name="ci_csrf_token" value="[^"]*"' "$LOGIN_PAGE" \
    | sed -E 's/.*value="([^"]*)"/\1/')"

if [ -z "$CSRF_TOKEN" ]; then
    echo "unhealthy-hosts.sh: could not find CSRF token on login page" >&2
    exit 1
fi

LOGIN_STATUS="$(curl_mp -X POST "$MP_URL/login/index" \
    --data-urlencode "ci_csrf_token=$CSRF_TOKEN" \
    --data-urlencode "username=$MP_USER" \
    --data-urlencode "password=$MP_PASSWORD" \
    --data-urlencode "type_form=login" \
    --data-urlencode "timezone=UTC" \
    -o /dev/null -w '%{http_code}')"

if [ "$LOGIN_STATUS" != "200" ] && [ "$LOGIN_STATUS" != "302" ]; then
    echo "unhealthy-hosts.sh: login request failed (HTTP $LOGIN_STATUS)" >&2
    exit 1
fi

# Confirm the session actually authenticated (a failed login just redisplays
# the login form instead of the app).
WELCOME_URL="$(curl_mp "$MP_URL/welcome/index" -o /dev/null -w '%{url_effective}')"
case "$WELCOME_URL" in
    */login*)
        echo "unhealthy-hosts.sh: login failed, still on login page" >&2
        exit 1
        ;;
esac

# --- Health diagnostic categories --------------------------------------------
#
# These mirror exactly what the Mission Portal "Health" dropdown links to
# (see /welcome/index -> .CFE_HEALTH block): each entry is
# "<url-slug>:<view-template-name>". The SQL that defines each category is
# rendered server-side into the view template (as the logged-in user would
# see it, respecting that user's dismissed-host list) and is executed exactly
# as the browser would execute it, via the advancedreports "run query"
# endpoint.

CATEGORIES="
missing-reporting-data:hostsNeverCollected
deleted-hosts-report:deletedHostsReport
unreachable-hosts:notRecentlyCollected
outdated-reporting-data:agentNotRunRecently
policy-errors:lastAgentRunUnsuccessful
duplicate-ids:hostsUsingSameIdentity
duplicate-hostnames:hostsUsingSameName
"

for entry in $CATEGORIES; do
    slug="${entry%%:*}"
    view="${entry#*:}"

    view_html="$(curl_mp "$MP_URL/advancedreports/hostDiagnosticView/$view")"

    sql="$(printf '%s' "$view_html" | python3 -c '
import re, sys, html
data = sys.stdin.read()
m = re.search(r"<textarea[^>]*id=\"angularSQLString\"[^>]*>(.*?)</textarea>", data, re.S)
if m:
    print(html.unescape(m.group(1)).strip())
')"

    if [ -z "$sql" ]; then
        echo "unhealthy-hosts.sh: could not extract SQL for $slug" >&2
        continue
    fi

    encoded_sql="$(python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))' "$sql")"
    encoded_api_url="$(python3 -c 'import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))' "/health-diagnostic/report/$view")"

    # Some diagnostics (e.g. missing-reporting-data, deleted-hosts-report) read
    # from internal tables that the ad-hoc SQL sandbox rejects unless the
    # request also names the whitelisted health-diagnostic report it
    # corresponds to, via apiUrl - exactly as the Health page's own UI does.
    result="$(curl_mp -X POST "$MP_URL/advancedreports/results/" \
        -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
        -H 'X-Requested-With: XMLHttpRequest' \
        --data "SQLString=$encoded_sql&sortColumn=&sortDescending=false&skip=0&limit=1000000&includes=&excludes=&apiUrl=$encoded_api_url")"

    printf '%s' "$result" | python3 -c "
import json, sys
category = sys.argv[1]
try:
    data = json.loads(sys.stdin.read())
except ValueError as exc:
    print('unhealthy-hosts.sh: bad response for %s: %s' % (category, exc), file=sys.stderr)
    sys.exit(0)
if not isinstance(data, dict):
    print('unhealthy-hosts.sh: query error for %s: %r' % (category, data), file=sys.stderr)
    sys.exit(0)
for row in data.get('rows', []):
    if row:
        print('%s,%s' % (category, row[0]))
" "$slug"
done
```