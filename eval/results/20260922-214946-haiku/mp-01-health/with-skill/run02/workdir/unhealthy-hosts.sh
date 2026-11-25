#!/bin/bash
set -euo pipefail

# Credentials from environment
MP_URL="${MP_URL:?MP_URL not set}"
MP_USER="${MP_USER:?MP_USER not set}"
MP_PASSWORD="${MP_PASSWORD:?MP_PASSWORD not set}"

# Create temporary netrc file
NETRC=$(mktemp)
trap "rm -f $NETRC" EXIT
printf 'machine %s login %s password %s\n' \
  "${MP_URL#https://}" \
  "$MP_USER" "$MP_PASSWORD" > "$NETRC"
chmod 600 "$NETRC"

# Helper function to make API calls
mp_api() {
  local method=$1
  local endpoint=$2
  local data=${3:-}

  local curl_opts=("-k" "-sS" "-H" "Content-Type: application/json" "-X" "$method")

  if [ -z "$data" ]; then
    curl "${curl_opts[@]}" --netrc-file "$NETRC" "$MP_URL$endpoint"
  else
    curl "${curl_opts[@]}" --netrc-file "$NETRC" -d "$data" "$MP_URL$endpoint"
  fi
}

# Get health diagnostic status
status=$(mp_api GET /api/health-diagnostic/status)

# Extract categories (all keys except 'total' and 'totalFailed')
categories=$(echo "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

# For each category, get the report and list flagged hosts
for category in $categories; do
  report=$(mp_api POST "/api/health-diagnostic/report/$category" '{"limit": 10000}')

  # Extract hostkeys from rows - first element of each row is the key
  echo "$report" | jq -r --arg cat "$category" '.data[0].rows[]? | $cat + "," + .[0]'
done
