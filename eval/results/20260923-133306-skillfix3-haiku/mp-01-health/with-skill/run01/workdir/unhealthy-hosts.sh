#!/usr/bin/env bash
# Query Mission Portal Health page for unhealthy hosts
# Output: <category>,<hostkey> (one per line)
# Requires: MP_URL, MP_USER, MP_PASSWORD

set -euo pipefail

if [ -z "${MP_URL:-}" ] || [ -z "${MP_USER:-}" ] || [ -z "${MP_PASSWORD:-}" ]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD environment variables required" >&2
    exit 1
fi

mp() {
    local -a body=()
    [ $# -ge 3 ] && body=(-H 'Content-Type: application/json' --data-binary "$3")
    printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
        curl -sS --fail-with-body -k -K - -X "$1" "${body[@]}" "$MP_URL$2"
}

# Get health status to identify all health categories
status=$(mp GET /api/health-diagnostic/status)

# Extract category names (all keys except total and totalFailed)
categories=$(echo "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

# For each category, fetch the report and output category,hostkey
while IFS= read -r category; do
    report=$(mp POST /api/health-diagnostic/report/"$category" '{"limit": 10000}')

    # Extract hostkey (first element of each row) with category prefix
    echo "$report" | jq -r '.data[0].rows[] | "'"$category"'," + .[0]'
done <<< "$categories"
