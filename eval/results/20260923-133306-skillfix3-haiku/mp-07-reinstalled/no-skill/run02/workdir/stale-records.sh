#!/bin/bash

set -euo pipefail

MP_URL="${MP_URL?Mission Portal URL not set}"
MP_USER="${MP_USER?Mission Portal user not set}"
MP_PASSWORD="${MP_PASSWORD?Mission Portal password not set}"

# Fetch all hosts from Mission Portal API
RESPONSE=$(curl -s -k -u "$MP_USER:$MP_PASSWORD" "$MP_URL/api/host")

# Process the JSON to find stale records
# Group by hostname, find those with multiple hostkeys, output stale ones
echo "$RESPONSE" | jq -r '
.data |
group_by(.hostname) |
.[] |
select(length > 1) |
. as $group |
(
  # Determine current hostkey (most recently reported/seen)
  ($group | max_by(.lastreport | tonumber) | .id) as $current
  |
  # Output each stale record
  $group[] |
  select(.id != $current) |
  [.id, $current, .hostname, .ip] |
  join(",")
)
'
