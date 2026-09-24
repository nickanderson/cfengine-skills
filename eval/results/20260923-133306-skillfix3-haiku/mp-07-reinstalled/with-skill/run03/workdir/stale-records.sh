#!/usr/bin/env bash

set -euo pipefail

# Validate required environment variables
for var in MP_URL MP_USER MP_PASSWORD; do
  if [ -z "${!var:-}" ]; then
    echo "Error: $var not set" >&2
    exit 1
  fi
done

# Use insecure TLS by default (self-signed cert), allow override with MP_CACERT
tls=(-k)
if [ -n "${MP_CACERT:-}" ]; then
  tls=(--cacert "$MP_CACERT")
fi

# Helper function to call Mission Portal API
mp() {
  local -a body=()
  [ $# -ge 3 ] && body=(-H 'Content-Type: application/json' --data-binary "$3")
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
    curl -sS --fail-with-body "${tls[@]}" -K - -X "$1" "${body[@]}" "$MP_URL$2"
}

# Query all hosts with agent status to determine which is currently active
# Use agent execution timestamp as the primary indicator of activity
query='SELECT h.hostkey, h.hostname, h.ipaddress, h.lastreporttimestamp, a.lastagentlocalexecutiontimestamp FROM hosts h LEFT JOIN agentstatus a ON h.hostkey = a.hostkey ORDER BY h.hostname, COALESCE(a.lastagentlocalexecutiontimestamp, h.lastreporttimestamp) DESC'

result=$(mp POST /api/query "{\"query\": \"$query\"}")

# Parse the result with jq to find stale records
# Group by hostname, find duplicates, and output stale entries
echo "$result" | jq -r '
  .data[0].rows as $rows |
  
  # Group rows by hostname (field 1)
  ($rows | group_by(.[1])) as $groups |
  
  # Process only groups with multiple entries (duplicate hostnames)
  $groups[] |
  select(length > 1) |
  
  # For each duplicate group, the first entry (after sorting by timestamp DESC) is current
  # All others are stale
  . as $group |
  ($group[0][0]) as $current_hostkey |
  ($group[0][1]) as $hostname |
  
  # Output each stale record
  $group[1:] |
  .[] |
  "\(.[0]),\($current_hostkey),\($hostname),\(.[2])"
'

exit 0
