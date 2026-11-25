#!/bin/bash

# Query Mission Portal Health page for unhealthy hosts
# Output format: <category>,<hostkey>

set -e

# Require credentials from environment
if [[ -z "$MP_URL" || -z "$MP_USER" || -z "$MP_PASSWORD" ]]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD must be set" >&2
    exit 1
fi

# Extract hostname from MP_URL for netrc
hostname=$(echo "$MP_URL" | sed -E 's|.*://([^/:]+).*|\1|')

# Create temporary netrc file with credentials
netrc=$(mktemp)
trap "rm -f '$netrc'" EXIT
printf 'machine %s login %s password %s\n' "$hostname" "$MP_USER" "$MP_PASSWORD" > "$netrc"
chmod 600 "$netrc"

# Get health diagnostic status to enumerate all categories
status=$(curl -sS -k --netrc-file "$netrc" "$MP_URL/api/health-diagnostic/status")

# Extract category names (exclude 'total' and 'totalFailed')
categories=$(echo "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

# For each category, fetch the report and output category,key pairs
for category in $categories; do
    curl -sS -k --netrc-file "$netrc" \
        -H "Content-Type: application/json" \
        -d '{"limit": 10000}' \
        "$MP_URL/api/health-diagnostic/report/$category" | \
        jq -r ".data[0].rows[]? | \"$category,\(.[0])\""
done
