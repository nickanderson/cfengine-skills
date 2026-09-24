#!/usr/bin/env bash
# Prints one line per host flagged unhealthy on Mission Portal's Health page:
#   <category>,<hostkey>
#
# Required environment:
#   MP_URL       Mission Portal base URL, e.g. https://hub.example.com
#   MP_USER      API user
#   MP_PASSWORD  API user's password
# Optional:
#   MP_CACERT    Path to the hub's CA/server certificate. If unset, certificate
#                verification is skipped (-k), since the hub is known to use a
#                self-signed certificate.

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

curl_cert_args=()
if [ -n "${MP_CACERT:-}" ]; then
    curl_cert_args=(--cacert "$MP_CACERT")
else
    curl_cert_args=(-k)
    echo "unhealthy-hosts.sh: MP_CACERT not set; skipping certificate verification (-k)" >&2
fi

# Calls the API without ever putting the password on the command line (it
# would otherwise be visible to other users via `ps`). curl reads it from a
# tiny config fed on stdin instead.
api() {
    local method="$1" path="$2" data="${3:-}"
    local args=(-sS -f -X "$method" "${curl_cert_args[@]}" "$MP_URL$path")
    if [ -n "$data" ]; then
        args+=(-H "Content-Type: application/json" --data "$data")
    fi
    curl -K - "${args[@]}" <<CURLCFG
user = "$MP_USER:$MP_PASSWORD"
CURLCFG
}

status_json=$(api GET /api/health-diagnostic/status)

categories=$(printf '%s' "$status_json" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

while IFS= read -r category; do
    [ -z "$category" ] && continue
    report_json=$(api POST "/api/health-diagnostic/report/$category" '{"limit": 100000}')
    printf '%s' "$report_json" | jq -r --arg cat "$category" '.data[0].rows[]? | $cat + "," + .[0]'
done <<< "$categories"
