#!/bin/bash

# Query CFEngine Mission Portal for unhealthy hosts
# Output format: <category>,<hostkey>

MP_URL="${MP_URL}"
MP_USER="${MP_USER}"
MP_PASSWORD="${MP_PASSWORD}"

if [[ -z "$MP_URL" || -z "$MP_USER" || -z "$MP_PASSWORD" ]]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD environment variables must be set" >&2
    exit 1
fi

# Query the Mission Portal health API endpoint
RESPONSE=$(curl -s -k --user "$MP_USER:$MP_PASSWORD" "$MP_URL/api/health" 2>/dev/null)

# Parse the JSON response to extract unhealthy hosts
# Look for hosts with health issues and extract their keys and categories
echo "$RESPONSE" | jq -r '.hosts[] | select(.status != "ok") | "\(.category),\(.hostkey)"' 2>/dev/null || true
