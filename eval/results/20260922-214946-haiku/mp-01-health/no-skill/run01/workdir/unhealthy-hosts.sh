#!/bin/bash

# Query CFEngine Enterprise Mission Portal for unhealthy hosts
# Output format: <category>,<hostkey>

MP_URL="${MP_URL}"
MP_USER="${MP_USER}"
MP_PASSWORD="${MP_PASSWORD}"

if [ -z "$MP_URL" ] || [ -z "$MP_USER" ] || [ -z "$MP_PASSWORD" ]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD environment variables must be set" >&2
    exit 1
fi

# Query the agentstatus table for hosts with unhealthy status
# Output hosts that are not "OK"
curl -s -k -L --insecure -X POST -H "Content-Type: application/json" \
    -u "${MP_USER}:${MP_PASSWORD}" \
    -d '{"query": "select hostkey, lastagentexecutionstatus from agentstatus where lastagentexecutionstatus != '"'"'OK'"'"'"}' \
    "${MP_URL}/api/query" 2>/dev/null | \
    jq -r '.data[0].rows[] | "\(.[1]),\(.[0])"' 2>/dev/null || true
