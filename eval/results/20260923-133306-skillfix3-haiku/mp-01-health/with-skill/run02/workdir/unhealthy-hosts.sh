#!/usr/bin/env bash
set -euo pipefail

# Configuration from environment
MP_URL="${MP_URL:-}"
MP_USER="${MP_USER:-}"
MP_PASSWORD="${MP_PASSWORD:-}"

if [ -z "$MP_URL" ] || [ -z "$MP_USER" ] || [ -z "$MP_PASSWORD" ]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD environment variables are required" >&2
    exit 1
fi

# TLS configuration - skip verification for self-signed cert
TLS_OPTS=(-k)

# Helper function to make API calls
mp_api() {
    local method=$1
    local path=$2
    local data=${3:-}

    local curl_opts=(-sS --fail-with-body "${TLS_OPTS[@]}" -X "$method")

    if [ -n "$data" ]; then
        curl_opts+=(-H 'Content-Type: application/json' --data-binary "$data")
    fi

    # Pass credentials via stdin to avoid them appearing in process list
    printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" | \
        curl "${curl_opts[@]}" -K - "$MP_URL$path"
}

# Get health status to find categories with unhealthy hosts
status=$(mp_api GET /api/health-diagnostic/status)

# Extract categories (keys other than 'total' and 'totalFailed') that have failures
categories=$(echo "$status" | jq -r 'to_entries[] | select(.value > 0 and .key != "total" and .key != "totalFailed") | .key')

# For each category, get the report and print unhealthy hosts
for category in $categories; do
    # Get the report for this category
    report=$(mp_api POST "/api/health-diagnostic/report/$category" '{"limit": 10000}')

    # Extract the 'key' field (first column of each row) and print with category
    echo "$report" | jq -r --arg cat "$category" '.data[0].rows[] | "\($cat),\(.[0])"'
done
