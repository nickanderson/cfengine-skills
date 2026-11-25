#!/usr/bin/env bash
# Prints "<category>,<hostkey>" for every host flagged unhealthy on the
# Mission Portal Health page.
#
# Needs MP_URL, MP_USER, MP_PASSWORD; MP_CACERT (the hub's certificate) optional.
set -euo pipefail

: "${MP_URL:?MP_URL is not set}"
: "${MP_USER:?MP_USER is not set}"
: "${MP_PASSWORD:?MP_PASSWORD is not set}"

tls=(-k)
[ -n "${MP_CACERT:-}" ] && tls=(--cacert "$MP_CACERT")

mp_host=$(printf '%s' "$MP_URL" | sed -E 's#^[a-zA-Z]+://##; s#/.*##; s#:.*##')
netrc=$(printf 'machine %s login %s password %s\n' "$mp_host" "$MP_USER" "$MP_PASSWORD")

mp() { # mp <METHOD> <path> [json-body] -> response body; fails on HTTP errors
  local method="$1" path="$2"
  local -a body=()
  [ $# -ge 3 ] && body=(-H 'Content-Type: application/json' --data-binary "$3")
  curl -sS --fail-with-body "${tls[@]}" --netrc-file <(printf '%s' "$netrc") \
    -X "$method" "${body[@]}" "${MP_URL%/}/api${path}"
}

status=$(mp GET /health-diagnostic/status)

categories=$(printf '%s' "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

while IFS= read -r category; do
  [ -n "$category" ] || continue
  report=$(mp POST "/health-diagnostic/report/$category" '{"limit": 10000}')
  printf '%s' "$report" | jq -r --arg category "$category" \
    '.data[0].rows[]? | [$category, .[0]] | @csv' |
    sed 's/"//g'
done <<< "$categories"
