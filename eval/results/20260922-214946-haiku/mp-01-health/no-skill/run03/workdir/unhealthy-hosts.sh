#!/bin/bash

set -euo pipefail

if [ -z "${MP_URL:-}" ] || [ -z "${MP_USER:-}" ] || [ -z "${MP_PASSWORD:-}" ]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD environment variables must be set" >&2
    exit 1
fi

# Fetch health data from Mission Portal's health endpoint
health_data=$(curl -s --insecure \
    --user "${MP_USER}:${MP_PASSWORD}" \
    "${MP_URL}/api/health" 2>/dev/null || echo "")

# Parse the response if it's valid JSON
if [ -n "$health_data" ] && echo "$health_data" | jq . >/dev/null 2>&1; then
    echo "$health_data" | jq -r '
      .[] |
      select(.health != "healthy") |
      "\(.health),\(.hostkey)"
    ' 2>/dev/null
fi
