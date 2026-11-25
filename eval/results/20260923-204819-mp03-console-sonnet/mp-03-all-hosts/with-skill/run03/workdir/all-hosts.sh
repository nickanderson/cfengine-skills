#!/usr/bin/env bash
# Print one CSV line per host known to CFEngine Mission Portal:
#   <hostkey>,<hostname>,<ip address>
# No header, nothing else on stdout.
#
# Needs MP_URL, MP_USER, MP_PASSWORD in the environment.
# MP_CACERT (path to the hub's certificate) is optional; without it,
# certificate verification is skipped (-k), since the hub uses a
# self-signed certificate.
set -euo pipefail

: "${MP_URL:?MP_URL is required}"
: "${MP_USER:?MP_USER is required}"
: "${MP_PASSWORD:?MP_PASSWORD is required}"

url=${MP_URL%/}

tls=(-k)
if [ -n "${MP_CACERT:-}" ]; then
  tls=(--cacert "$MP_CACERT")
fi

query() {  # query <sql> -> response body on stdout
  local sql=$1
  local body
  body=$(jq -n --arg q "$sql" --argjson skip "$skip" --argjson limit "$limit" \
    '{query: $q, skip: $skip, limit: $limit}')
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
    curl -sS --fail-with-body "${tls[@]}" -K - \
      -H 'Content-Type: application/json' --data-binary "$body" \
      "$url/api/query"
}

sql='SELECT hostkey, hostname, ipaddress FROM hosts'
skip=0
limit=5000

while :; do
  response=$(query "$sql")
  rowcount=$(printf '%s' "$response" | jq '.data[0].rowCount')

  printf '%s' "$response" |
    jq -r '.data[0].rows[] | map(tostring) | join(",")'

  [ "$rowcount" -lt "$limit" ] && break
  skip=$((skip + limit))
done
