#!/bin/bash

set -u

MP_URL="${MP_URL}"
MP_USER="${MP_USER}"
MP_PASSWORD="${MP_PASSWORD}"

if [ -z "$MP_URL" ] || [ -z "$MP_USER" ] || [ -z "$MP_PASSWORD" ]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD environment variables must be set" >&2
    exit 1
fi

# Fetch hosts and identify stale records
# Group by hostname+ip, sort by lastreport, output stale ones (non-current)
curl -s -k -u "${MP_USER}:${MP_PASSWORD}" \
    "${MP_URL}/api/host" | \
jq -r '
    .data |
    group_by(.hostname + "|" + .ip) |
    .[] |
    select(length > 1) |
    sort_by(.lastreport | tonumber) | reverse |
    .[0] as $current |
    .[1:] |
    .[] |
    "\(.id),\($current.id),\(.hostname),\(.ip)"
'
