#!/bin/bash

set -euo pipefail

# Get status to find which categories have flagged hosts
status=$(curl -sS -k -u "$MP_USER:$MP_PASSWORD" "$MP_URL/api/health-diagnostic/status")

# Extract all category keys (skip 'total' and 'totalFailed')
categories=$(echo "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

# For each category, fetch the report and output hosts
for category in $categories; do
  response=$(curl -sS -k -u "$MP_USER:$MP_PASSWORD" "$MP_URL/api/health-diagnostic/report/$category" \
    -H "Content-Type: application/json" \
    -d '{"limit": 10000}')

  # Extract hostkeys from rows and output as category,hostkey
  echo "$response" | jq -r '.data[0].rows[]? | "'"$category"',\(.[0])"' 2>/dev/null || true
done
