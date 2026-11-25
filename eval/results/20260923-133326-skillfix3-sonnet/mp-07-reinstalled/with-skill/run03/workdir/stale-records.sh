#!/usr/bin/env bash
# Find leftover Mission Portal host records left behind by reinstalled
# machines: same hostname + IP address reporting under an old hostkey that
# has stopped, while a newer hostkey for the same hostname/IP is current.
#
# Needs: MP_URL, MP_USER, MP_PASSWORD
# Optional: MP_CACERT (path to the hub's certificate; otherwise TLS
#           verification is skipped, since the hub uses a self-signed cert)
#
# Prints one CSV line per leftover record on stdout:
#   <stale hostkey>,<current hostkey>,<hostname>,<ip>

set -euo pipefail

: "${MP_URL:?MP_URL is required}"
: "${MP_USER:?MP_USER is required}"
: "${MP_PASSWORD:?MP_PASSWORD is required}"

tls=(-k)
[ -n "${MP_CACERT:-}" ] && tls=(--cacert "$MP_CACERT")

query='WITH ranked AS (
  SELECT hostkey, hostname, ipaddress, lastreporttimestamp,
         ROW_NUMBER() OVER (PARTITION BY hostname, ipaddress ORDER BY lastreporttimestamp DESC) AS rn
  FROM hosts
)
SELECT r2.hostkey AS stale_hostkey, r1.hostkey AS current_hostkey, r1.hostname, r1.ipaddress
FROM ranked r1
JOIN ranked r2 ON r1.hostname = r2.hostname AND r1.ipaddress = r2.ipaddress
WHERE r1.rn = 1 AND r2.rn > 1'

body=$(jq -n --arg q "$query" '{query: $q}')

response=$(printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
  curl -sS --fail-with-body "${tls[@]}" -K - \
    -X POST -H 'Content-Type: application/json' --data-binary "$body" \
    "$MP_URL/api/query")

echo "$response" | jq -r '.data[0].rows[]? | @csv' | tr -d '"'
