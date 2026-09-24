#!/usr/bin/env bash
#
# List the hosts currently flagged as unhealthy on Mission Portal's Health
# page. Prints one "<category>,<hostkey>" line per flagged host on stdout.
#
# Requires: curl, jq
#
# Configuration (environment variables):
#   MP_URL       Base URL of the hub's Mission Portal, e.g. https://hub.example.com
#   MP_USER      API user name
#   MP_PASSWORD  API user password
#   MP_CACERT    Optional path to the hub's CA/server certificate for curl's
#                --cacert. If unset, certificate verification is skipped
#                (-k), since the hub is documented to use a self-signed cert.

set -euo pipefail

: "${MP_URL:?MP_URL must be set to the Mission Portal base URL}"
: "${MP_USER:?MP_USER must be set to the API user name}"
: "${MP_PASSWORD:?MP_PASSWORD must be set to the API user password}"

base_url="${MP_URL%/}"

curl_opts=(-s -u "${MP_USER}:${MP_PASSWORD}")
if [ -n "${MP_CACERT:-}" ]; then
    curl_opts+=(--cacert "${MP_CACERT}")
else
    curl_opts+=(-k)
    echo "unhealthy-hosts.sh: MP_CACERT not set, skipping certificate verification (-k)" >&2
fi

fail() {
    echo "unhealthy-hosts.sh: $*" >&2
    exit 1
}

do_get() {
    local path="$1"
    local resp status body
    resp=$(curl "${curl_opts[@]}" -w '\n%{http_code}' "${base_url}${path}") || fail "request to ${path} failed"
    status=${resp##*$'\n'}
    body=${resp%$'\n'*}
    [ "$status" -ge 200 ] && [ "$status" -lt 300 ] || fail "GET ${path} returned HTTP ${status}: ${body}"
    printf '%s' "$body"
}

do_post() {
    local path="$1" data="$2"
    local resp status body
    resp=$(curl "${curl_opts[@]}" -w '\n%{http_code}' \
        -H 'Content-Type: application/json' -X POST -d "$data" "${base_url}${path}") \
        || fail "request to ${path} failed"
    status=${resp##*$'\n'}
    body=${resp%$'\n'*}
    [ "$status" -ge 200 ] && [ "$status" -lt 300 ] || fail "POST ${path} returned HTTP ${status}: ${body}"
    printf '%s' "$body"
}

status_json=$(do_get /api/health-diagnostic/status)

categories=$(printf '%s' "$status_json" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

while IFS= read -r category; do
    [ -n "$category" ] || continue
    report_json=$(do_post "/api/health-diagnostic/report/${category}" '{"limit":10000}')
    printf '%s' "$report_json" | jq -r --arg category "$category" \
        '.data[0].rows[]? | "\($category),\(.[0])"'
done <<< "$categories"
