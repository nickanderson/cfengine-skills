#!/usr/bin/env bash
# List hosts flagged on Mission Portal's Health page, one "<category>,<hostkey>" per line.
# Needs: MP_URL, MP_USER, MP_PASSWORD. Optional: MP_CACERT (hub certificate;
# without it, TLS verification is skipped because the hub cert is self-signed).
set -euo pipefail

: "${MP_URL:?MP_URL is not set}" "${MP_USER:?MP_USER is not set}" "${MP_PASSWORD:?MP_PASSWORD is not set}"
base=${MP_URL%/}

if [ -n "${MP_CACERT:-}" ]; then tls=(--cacert "$MP_CACERT"); else tls=(-k); fi

# Credentials go to curl via a process-substitution netrc, never on the command line.
host=$(printf '%s' "$base" | sed -E 's#^[a-z]+://##; s#[:/].*##')
api() { # api METHOD PATH [BODY]
  local args=(-sS --fail-with-body "${tls[@]}" -X "$1")
  [ $# -ge 3 ] && args+=(-H 'Content-Type: application/json' --data "$3")
  curl "${args[@]}" \
    --netrc-file <(printf 'machine %s login %s password %s\n' "$host" "$MP_USER" "$MP_PASSWORD") \
    "$base$2"
}

# Categories come from /status keys (report_ids omits hostsUsingSameName).
status=$(api GET /api/health-diagnostic/status) || { echo "status request failed: $status" >&2; exit 1; }
categories=$(jq -r 'to_entries[] | select(.key != "total" and .key != "totalFailed")
                    | select((.value|tonumber) > 0) | .key' <<<"$status")

for cat in $categories; do
  skip=0; limit=1000
  while :; do
    resp=$(api POST "/api/health-diagnostic/report/$cat" "{\"skip\":$skip,\"limit\":$limit}") \
      || { echo "report $cat failed: $resp" >&2; exit 1; }
    # First column ("key") is the hostkey in every report.
    n=$(jq '.data[0].rows | length' <<<"$resp")
    jq -r --arg c "$cat" '.data[0].rows[] | "\($c),\(.[0])"' <<<"$resp"
    [ "$n" -lt "$limit" ] && break
    skip=$((skip + limit))
  done
done
