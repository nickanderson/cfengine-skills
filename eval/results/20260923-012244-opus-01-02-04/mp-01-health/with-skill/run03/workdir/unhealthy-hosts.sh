#!/usr/bin/env bash
# List hosts flagged by Mission Portal's Health page as "<category>,<hostkey>".
# Env: MP_URL, MP_USER, MP_PASSWORD; optional MP_CACERT (otherwise TLS
# verification is skipped, since the hub certificate is self-signed).
set -euo pipefail
: "${MP_URL:?MP_URL not set}" "${MP_USER:?MP_USER not set}" "${MP_PASSWORD:?MP_PASSWORD not set}"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

base=${MP_URL%/}
if [ -n "${MP_CACERT:-}" ]; then tls=(--cacert "$MP_CACERT"); else tls=(-k); fi

api() { # api METHOD PATH [BODY]
  local args=(-sS --fail-with-body "${tls[@]}" -X "$1")
  [ $# -ge 3 ] && args+=(-H 'Content-Type: application/json' --data-binary "$3")
  # Credentials go to curl on stdin, never on the command line.
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" | curl "${args[@]}" -K - "$base$2"
}

status=$(api GET /api/health-diagnostic/status)
# Categories come from /status keys (report_ids omits hostsUsingSameName).
for cat in $(jq -r 'to_entries[] | select(.key != "total" and .key != "totalFailed")
                    | select((.value|tonumber) > 0) | .key' <<<"$status"); do
  skip=0; limit=1000
  while :; do
    page=$(api POST "/api/health-diagnostic/report/$cat" "{\"skip\":$skip,\"limit\":$limit}")
    n=$(jq '.data[0].rows | length' <<<"$page")
    # First column ("key") is the hostkey in every report.
    jq -r --arg c "$cat" '.data[0].rows[] | "\($c),\(.[0])"' <<<"$page"
    [ "$n" -lt "$limit" ] && break
    skip=$((skip + limit))
  done
done
