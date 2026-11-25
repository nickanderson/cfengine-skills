#!/usr/bin/env bash
# List hosts flagged as unhealthy on Mission Portal's Health page.
# Output: <category>,<hostkey>   (category = health-diagnostic report id)
# Requires: MP_URL, MP_USER, MP_PASSWORD; curl, jq.
set -euo pipefail

: "${MP_URL:?MP_URL not set}" "${MP_USER:?MP_USER not set}" "${MP_PASSWORD:?MP_PASSWORD not set}"
API="${MP_URL%/}/api/health-diagnostic"
PAGE=1000

api() { # api <method> <path> [json-body]
  curl -sSfk -u "$MP_USER:$MP_PASSWORD" -X "$1" \
       -H 'Content-Type: application/json' ${3:+-d "$3"} "$API/$2"
}

# The status summary lists every category the Health page counts (including
# hostsUsingSameName, which is missing from /report_ids) with its count.
status=$(api GET status)
categories=$(jq -r 'to_entries[]
  | select(.key != "total" and .key != "totalFailed")
  | select((.value | tonumber? // 0) > 0) | .key' <<<"$status")

for cat in $categories; do
  skip=0
  while :; do
    resp=$(api POST "report/$cat" "{\"limit\":$PAGE,\"skip\":$skip}")
    # Hostkey is in the column named "key" (present in every report).
    rows=$(jq -r '.data[0] as $d
      | ($d.header | map(.columnName) | index("key")) as $i
      | $d.rows[] | .[$i]' <<<"$resp")
    n=$(jq -r '.data[0].rows | length' <<<"$resp")
    [ -n "$rows" ] && sed "s/^/$cat,/" <<<"$rows"
    [ "$n" -lt "$PAGE" ] && break
    skip=$((skip + PAGE))
  done
done
