#!/bin/bash

set -e

MP_URL="${MP_URL:-https://192.168.56.2}"
MP_USER="${MP_USER:-admin}"
MP_PASSWORD="${MP_PASSWORD:-<redacted>}"

# Get health report IDs (categories)
report_ids=$(curl -s -k -u "${MP_USER}:${MP_PASSWORD}" \
  "${MP_URL}/api/health-diagnostic/report_ids" | jq -r '.[]')

# Also get status keys that might not be in report_ids
status_keys=$(curl -s -k -u "${MP_USER}:${MP_PASSWORD}" \
  "${MP_URL}/api/health-diagnostic/status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

# Combine and deduplicate report IDs
all_ids=$(printf "%s\n" "$report_ids" "$status_keys" | sort -u)

# For each report ID, fetch the hosts
for rid in $all_ids; do
  curl -s -k -u "${MP_USER}:${MP_PASSWORD}" \
    "${MP_URL}/api/health-diagnostic/report/${rid}" \
    -H "Content-Type: application/json" \
    -d '{"limit": 10000}' 2>/dev/null | \
    jq -r ".data[0].rows[]? | .[0]" 2>/dev/null | \
    while read -r hostkey; do
      [ -n "$hostkey" ] && echo "$rid,$hostkey"
    done
done
