#!/bin/bash

# Query CFEngine Mission Portal Health page for unhealthy hosts
# Output format: <category>,<hostkey>

MP_URL="${MP_URL:?MP_URL not set}"
MP_USER="${MP_USER:?MP_USER not set}"
MP_PASSWORD="${MP_PASSWORD:?MP_PASSWORD not set}"

# Query the Mission Portal API for unhealthy hosts
RESPONSE=$(curl -s -k \
  -u "${MP_USER}:${MP_PASSWORD}" \
  -H "Accept: application/vnd.cfengine.enterprise-v1+json" \
  "${MP_URL}/api/health" 2>/dev/null)

# Parse the JSON response to extract unhealthy hosts
# Output in format: category,hostkey
if echo "$RESPONSE" | jq empty 2>/dev/null; then
  echo "$RESPONSE" | jq -r '
    .data[]? |
    select(.health != "good" and .health != null and .hostkey != null) |
    "\(.health),\(.hostkey)"
  ' 2>/dev/null | grep -v "^$"
fi
