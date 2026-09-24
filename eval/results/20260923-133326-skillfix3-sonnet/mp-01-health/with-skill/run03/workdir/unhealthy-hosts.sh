#!/usr/bin/env bash
# Lists hosts flagged unhealthy on the Mission Portal Health page.
#
# Needs: MP_URL, MP_USER, MP_PASSWORD
# Optional: MP_CACERT (path to the hub's certificate; without it, TLS
#           verification is skipped, since the hub uses a self-signed cert)
#
# Prints one line per flagged host to stdout:
#   <category>,<hostkey>
set -euo pipefail

: "${MP_URL:?Set MP_URL to the Mission Portal base URL}"
: "${MP_USER:?Set MP_USER to the Mission Portal username}"
: "${MP_PASSWORD:?Set MP_PASSWORD to the Mission Portal password}"

tls=(-k)
[ -n "${MP_CACERT:-}" ] && tls=(--cacert "$MP_CACERT")

mp() {  # mp <METHOD> <path> [json-body] -> response body; fails on HTTP errors
  local method=$1 path=$2 data=${3:-}
  local -a body=()
  [ -n "$data" ] && body=(-H 'Content-Type: application/json' --data-binary "$data")
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
    curl -sS --fail-with-body "${tls[@]}" -K - -X "$method" "${body[@]}" "$MP_URL$path"
}

status=$(mp GET /api/health-diagnostic/status)

categories=$(printf '%s' "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

while IFS= read -r category; do
  [ -z "$category" ] && continue
  report=$(mp POST "/api/health-diagnostic/report/$category" '{"limit":10000}')
  printf '%s' "$report" |
    jq -r --arg cat "$category" '.data[0].rows[]? | "\($cat),\(.[0])"'
done <<< "$categories"
