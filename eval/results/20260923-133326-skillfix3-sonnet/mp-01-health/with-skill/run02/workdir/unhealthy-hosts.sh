#!/usr/bin/env bash
# Prints "<category>,<hostkey>" for every host the Mission Portal Health page
# currently flags as unhealthy. Nothing else goes to stdout.
#
# Needs: MP_URL, MP_USER, MP_PASSWORD
# Optional: MP_CACERT (path to the hub's certificate; otherwise TLS verification is skipped)
set -euo pipefail

: "${MP_URL:?MP_URL is required}"
: "${MP_USER:?MP_USER is required}"
: "${MP_PASSWORD:?MP_PASSWORD is required}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

tls=(-k)
[ -n "${MP_CACERT:-}" ] && tls=(--cacert "$MP_CACERT")

mp() { # mp <METHOD> <path> [json-body] -> response body on stdout; fails on HTTP errors
  local -a body=()
  [ $# -ge 3 ] && body=(-H 'Content-Type: application/json' --data-binary "$3")
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
    curl -sS --fail-with-body "${tls[@]}" -K - -X "$1" "${body[@]}" "$MP_URL$2"
}

# Priority order matching the Health page: a host is reported only under the
# category closest to its root cause, so we assign each hostkey to the first
# matching category and skip it in any later one.
categories=(
  hostsNeverCollected
  notRecentlyCollected
  agentNotRunRecently
  lastAgentRunUnsuccessful
  hostsUsingSameIdentity
  hostsUsingSameName
  deletedHostsReport
)

status=$(mp GET /api/health-diagnostic/status)

declare -A seen=()

for category in "${categories[@]}"; do
  count=$(jq -r --arg c "$category" '.[$c] // 0' <<<"$status")
  [ "$count" -gt 0 ] || continue

  report=$(mp POST "/api/health-diagnostic/report/$category" '{"limit": 10000}')

  while IFS= read -r hostkey; do
    [ -n "$hostkey" ] || continue
    [ -n "${seen[$hostkey]:-}" ] && continue
    seen[$hostkey]=1
    echo "$category,$hostkey"
  done < <(jq -r '.data[0].rows[]? | .[0]' <<<"$report")
done
