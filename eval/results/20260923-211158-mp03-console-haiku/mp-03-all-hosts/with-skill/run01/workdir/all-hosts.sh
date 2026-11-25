#!/usr/bin/env bash
# Query CFEngine Mission Portal for all hosts; output CSV: hostkey,hostname,ipaddress
set -euo pipefail

# Credentials and URL from environment
: "${MP_URL:?Missing MP_URL}"
: "${MP_USER:?Missing MP_USER}"
: "${MP_PASSWORD:?Missing MP_PASSWORD}"

# TLS options: skip verification by default (self-signed), or use supplied certificate
tls=(-k)
[ -n "${MP_CACERT:-}" ] && tls=(--cacert "$MP_CACERT")

# Extract hostname from URL for netrc
host="${MP_URL#https://}"
host="${host#http://}"
host="${host%%/*}"

# Query the hosts view for all hosts
query='SELECT hostkey, hostname, ipaddress FROM hosts'

# Make the API call; print response body on success, exit nonzero on failure
response=$(curl -sS --fail-with-body "${tls[@]}" \
  --netrc-file <(printf 'machine %s login %s password %s\n' "$host" "$MP_USER" "$MP_PASSWORD") \
  -H 'Content-Type: application/json' \
  -d "{\"query\": \"$query\"}" \
  "$MP_URL/api/query")

# Extract rows from the JSON response and output as CSV
# Response structure: {"data": [{"header": [...], "rows": [[...], ...], "rowCount": N}]}
printf '%s\n' "$response" | jq -r '.data[0].rows[] | @csv'
