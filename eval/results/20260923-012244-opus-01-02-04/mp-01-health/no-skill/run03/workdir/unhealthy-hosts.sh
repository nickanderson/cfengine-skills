#!/usr/bin/env bash
# List hosts flagged by Mission Portal's Health page as "<category>,<hostkey>".
# Requires: curl, jq. Env: MP_URL, MP_USER, MP_PASSWORD (self-signed cert OK).
set -euo pipefail

: "${MP_URL:?MP_URL not set}" "${MP_USER:?MP_USER not set}" "${MP_PASSWORD:?MP_PASSWORD not set}"
base="${MP_URL%/}/api/health-diagnostic"
page=1000

api() { # api <url> [json-body]  -> POST if a body is given
  if [ $# -gt 1 ]; then
    curl -skf -u "$MP_USER:$MP_PASSWORD" -X POST -H 'Content-Type: application/json' -d "$2" "$1"
  else
    curl -skf -u "$MP_USER:$MP_PASSWORD" "$1"
  fi
}

# Health summary: {"<category>": <count>, ..., "totalFailed": n, "total": n}
status=$(api "$base/status") || { echo "failed to query $base/status" >&2; exit 1; }

# Every key except the aggregate totals is a health category; skip empty ones.
categories=$(jq -r 'to_entries[]
  | select(.key != "total" and .key != "totalFailed")
  | select((.value|tonumber? // 0) > 0) | .key' <<<"$status")

for cat in $categories; do
  skip=0
  while :; do
    resp=$(api "$base/report/$cat" "{\"limit\":$page,\"skip\":$skip}") \
      || { echo "failed to query report $cat" >&2; exit 1; }
    # First column ("key") of every report is the host key.
    jq -r --arg c "$cat" '.data[0].rows[] | "\($c),\(.[0])"' <<<"$resp"
    got=$(jq '.data[0].rows | length' <<<"$resp")
    total=$(jq '.data[0].rowCount // 0' <<<"$resp")
    skip=$((skip + got))
    [ "$got" -gt 0 ] && [ "$skip" -lt "$total" ] || break
  done
done
