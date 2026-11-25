#!/bin/bash

# Query CFEngine Enterprise Mission Portal for unhealthy hosts
# Output format: <category>,<hostkey>

set -e

# Get credentials and URL from environment
MP_URL="${MP_URL:?MP_URL not set}"
MP_USER="${MP_USER:?MP_USER not set}"
MP_PASSWORD="${MP_PASSWORD:?MP_PASSWORD not set}"

# Query the health table via the inventory API
# Filter for hosts with non-null health_category (indicating an unhealthy status)
curl -s -k -X POST \
  -u "$MP_USER:$MP_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"table":"health","select":["hostkey","health_category"]}' \
  "$MP_URL/api/inventory" | \
  jq -r '.data[0].rows[] | select(.[1] != null) | "\(.[1]),\(.[0])"'
