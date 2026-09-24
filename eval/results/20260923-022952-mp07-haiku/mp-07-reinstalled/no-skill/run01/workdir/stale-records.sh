#!/bin/bash

# Script to find stale host records in CFEngine Enterprise Mission Portal
# Prints: <stale hostkey>,<current hostkey>,<hostname>,<ip>
#
# Stale records are identified by hostname with multiple hostkeys.
# For each hostname, the current record is determined by:
#   1. Most recent lastreport timestamp (machine still reporting in)
#   2. If tied, use earliest firstseen (the older, original record is current)

MP_URL="${MP_URL:-https://localhost}"
MP_USER="${MP_USER:-admin}"
MP_PASSWORD="${MP_PASSWORD:-}"

curl -s -k -u "${MP_USER}:${MP_PASSWORD}" "${MP_URL}/api/host" 2>/dev/null | jq -r '
    .data | group_by(.hostname) | .[] |
    select(length > 1) |
    . as $hosts |
    # Find current record: sort by lastreport DESC, then firstseen ASC (older firstseen is more current)
    ($hosts | sort_by((.lastreport | tonumber) * -1, .firstseen | tonumber) | .[0]) as $current |
    # Output all other records as stale
    .[] | select(.id != $current.id) |
    "\(.id),\($current.id),\(.hostname),\(.ip)"
' 2>/dev/null || true
