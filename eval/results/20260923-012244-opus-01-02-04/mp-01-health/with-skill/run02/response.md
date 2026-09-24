I wrote `unhealthy-hosts.sh` and ran it against the hub (https://192.168.56.2) with your `MP_URL`, `MP_USER` and `MP_PASSWORD`. It listed 4 flagged hosts, which matches the hub's own `totalFailed` count of 4.

**Output:**
```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
```

What the categories mean on the Health page:
- **`agentNotRunRecently`** ("Outdated reporting data"): the hub can reach the host, but its agent hasn't run recently.
- **`deletedHostsReport`**: a host that was deleted but is still trying to report (from 192.168.56.4).
- **`hostsUsingSameName`** ("Duplicate hostnames"): these two keys report the same hostname.

**`unhealthy-hosts.sh`:**
```bash
#!/usr/bin/env bash
# Print "<category>,<hostkey>" for every host the Mission Portal Health page
# currently flags as unhealthy.
#
# Environment: MP_URL, MP_USER, MP_PASSWORD (required);
#              MP_CACERT (optional: hub certificate to verify against;
#              without it, TLS verification is skipped).
# Requires: curl, jq.
set -euo pipefail

: "${MP_URL:?MP_URL is not set}"
: "${MP_USER:?MP_USER is not set}"
: "${MP_PASSWORD:?MP_PASSWORD is not set}"
base=${MP_URL%/}

if [ -n "${MP_CACERT:-}" ]; then
    tls=(--cacert "$MP_CACERT")
else
    tls=(-k)
fi

# Credentials go to curl through a config on stdin (never on the command line).
# No Accept header: the hub answers 406 to "Accept: application/json".
api() {
    local method=$1 path=$2 body=${3:-}
    local args=(-sS --fail-with-body "${tls[@]}" -K - -X "$method")
    [ -n "$body" ] && args+=(-H 'Content-Type: application/json' --data "$body")
    printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
        curl "${args[@]}" "$base$path"
}

# Categories come from the keys of /status: /report_ids omits hostsUsingSameName.
status=$(api GET /api/health-diagnostic/status) ||
    { echo "error: GET /api/health-diagnostic/status failed: $status" >&2; exit 1; }
categories=$(jq -r 'keys[] | select(. != "total" and . != "totalFailed")' <<<"$status")

for cat in $categories; do
    # A category with zero hosts needs no request.
    [ "$(jq -r --arg c "$cat" '.[$c]' <<<"$status")" = 0 ] && continue
    report=$(api POST "/api/health-diagnostic/report/$cat" '{"limit": 100000}') ||
        { echo "error: report $cat failed: $report" >&2; exit 1; }
    # The first column, "key", is the hostkey in every report.
    jq -r --arg c "$cat" '.data[0].rows[] | "\($c),\(.[0])"' <<<"$report"
done
```

How it works:
- **Categories:** it takes the category names from `/api/health-diagnostic/status`, not from `/report_ids`, because `/report_ids` leaves out `hostsUsingSameName`.
- **Host keys:** it reads the hostkey from each report's first column (`key`), since not every report has a `hostkey` column.
- **Credentials:** they're passed to curl on stdin, so they don't appear in the process list.
- **Errors:** if a request fails, the error goes to stderr and the script exits non-zero.
- **One category per host:** the hub lists each host only under the category closest to the root cause.
- **Dismissed hosts:** hosts dismissed on the Health page are hidden for the account that dismissed them, so the output depends on whose credentials you use.
- **Certificate:** by default the script skips certificate checks (`-k`), because the hub's certificate is self-signed. To turn verification on, set `MP_CACERT` to the path of the hub's certificate.
- **Requirements:** curl 7.76 or newer (for `--fail-with-body`) and jq.