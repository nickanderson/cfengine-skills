#!/usr/bin/env bash
# Prints one CSV line per host known to Mission Portal: hostkey,hostname,ipaddress
#
# Needs: MP_URL, MP_USER, MP_PASSWORD
# Optional: MP_CACERT (path to the hub's certificate; otherwise TLS verification is skipped)
set -euo pipefail

: "${MP_URL:?MP_URL must be set (e.g. https://hub.example.com)}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

tls=(-k)
[ -n "${MP_CACERT:-}" ] && tls=(--cacert "$MP_CACERT")

query() { # query <json-body> -> response body; fails on HTTP errors
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
    curl -sS --fail-with-body "${tls[@]}" -K - -X POST \
      -H 'Content-Type: application/json' --data-binary "$1" \
      "$MP_URL/api/query"
}

# The `hosts` view is RBAC-filtered and excludes deleted hosts (unlike the
# underlying __hosts table). Page with skip/limit so no host is dropped
# regardless of how many the hub holds.
page_size=5000
skip=0
sql='SELECT hostkey, hostname, ipaddress FROM hosts ORDER BY hostkey'

while :; do
  body=$(jq -n --arg q "$sql" --argjson skip "$skip" --argjson limit "$page_size" \
    '{query: $q, skip: $skip, limit: $limit}')
  resp=$(query "$body")

  rows=$(echo "$resp" | jq -r '.data[0].rows[] | @tsv')
  if [ -n "$rows" ]; then
    echo "$rows" | awk -F'\t' '{print $1","$2","$3}'
  fi

  got=$(echo "$resp" | jq '.data[0].rows | length')
  [ "$got" -lt "$page_size" ] && break
  skip=$((skip + page_size))
done
