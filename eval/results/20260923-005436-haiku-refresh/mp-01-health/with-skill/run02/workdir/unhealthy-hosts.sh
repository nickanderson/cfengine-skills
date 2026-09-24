#!/bin/bash

# Query Mission Portal for unhealthy hosts, print: category,hostkey
# Requires: MP_URL, MP_USER, MP_PASSWORD environment variables

set -euo pipefail

if [[ -z "${MP_URL:-}" || -z "${MP_USER:-}" || -z "${MP_PASSWORD:-}" ]]; then
  echo "Error: MP_URL, MP_USER, MP_PASSWORD environment variables required" >&2
  exit 1
fi

# Function to make authenticated curl requests to MP
mp_api() {
  local method=$1 endpoint=$2 body=${3:-}

  if [[ -n "$body" ]]; then
    curl -sS -k \
      --basic -u "${MP_USER}:${MP_PASSWORD}" \
      -H "Content-Type: application/json" \
      -X "$method" \
      "$MP_URL/api$endpoint" \
      -d "$body"
  else
    curl -sS -k \
      --basic -u "${MP_USER}:${MP_PASSWORD}" \
      -X "$method" \
      "$MP_URL/api$endpoint"
  fi
}

# Get health status to find which categories have unhealthy hosts
status=$(mp_api GET "/health-diagnostic/status")

# Extract category names (all keys except 'total' and 'totalFailed')
categories=$(echo "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

# For each category with unhealthy hosts, fetch and print them
for category in $categories; do
  count=$(echo "$status" | jq ".\"$category\"")
  if [[ "$count" -gt 0 ]]; then
    # Fetch the report for this category, extracting the first column (key/hostkey)
    report=$(mp_api POST "/health-diagnostic/report/$category" '{"limit": 10000}')

    # Extract hostkeys from the first column of rows and print in format: category,hostkey
    echo "$report" | jq -r '.data[0].rows[] | .[0]' | while read -r hostkey; do
      echo "$category,$hostkey"
    done
  fi
done
