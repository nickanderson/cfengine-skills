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
