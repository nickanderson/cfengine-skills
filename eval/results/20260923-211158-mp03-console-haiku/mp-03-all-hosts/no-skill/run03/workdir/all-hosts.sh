#!/bin/bash

set -euo pipefail

# Mission Portal credentials and URL from environment variables
MP_URL="${MP_URL:?Missing MP_URL}"
MP_USER="${MP_USER:?Missing MP_USER}"
MP_PASSWORD="${MP_PASSWORD:?Missing MP_PASSWORD}"

# Get total number of hosts from first page
FIRST_RESPONSE=$(curl -s -k -u "$MP_USER:$MP_PASSWORD" "${MP_URL}/api/host")
TOTAL=$(echo "$FIRST_RESPONSE" | jq '.meta.total')

# Output all hosts on first page
echo "$FIRST_RESPONSE" | jq -r '.data[] | "\(.id),\(.hostname),\(.ip)"'

# Pagination: get remaining pages (each page has 50 hosts)
TOTAL_PAGES=$(( (TOTAL + 49) / 50 ))
for PAGE in $(seq 2 "$TOTAL_PAGES"); do
  curl -s -k -u "$MP_USER:$MP_PASSWORD" "${MP_URL}/api/host?page=$PAGE" | \
    jq -r '.data[] | "\(.id),\(.hostname),\(.ip)"'
done
