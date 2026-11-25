#!/bin/bash

set -e

if [[ -z "$MP_URL" || -z "$MP_USER" || -z "$MP_PASSWORD" ]]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD environment variables must be set" >&2
    exit 1
fi

# Create temporary files for cookies
temp_cookies=$(mktemp)
trap "rm -f $temp_cookies" EXIT

# Get CSRF token from login page
csrf_token=$(curl -s -k -c "$temp_cookies" "$MP_URL/login/index" 2>/dev/null | \
    grep 'ci_csrf_token' | grep -o 'value="[^"]*"' | cut -d'"' -f2)

if [[ -z "$csrf_token" ]]; then
    echo "Error: Failed to get CSRF token" >&2
    exit 1
fi

# Login with credentials and CSRF token
curl -s -k -b "$temp_cookies" -c "$temp_cookies" \
    -X POST -H "Content-Type: application/x-www-form-urlencoded" \
    -d "ci_csrf_token=$csrf_token&type_form=login&username=$MP_USER&password=$MP_PASSWORD&timezone=UTC" \
    "$MP_URL/login/index" > /dev/null 2>&1

# Define health diagnostic categories
categories=(
    "unreachable-hosts"
    "deleted-hosts-report"
    "duplicate-hostnames"
    "duplicate-ids"
    "missing-reporting-data"
    "outdated-reporting-data"
    "policy-errors"
)

# Extract unhealthy hosts from each health category
for category in "${categories[@]}"; do
    curl -s -k -b "$temp_cookies" \
        "$MP_URL/reports/health-diagnostic/$category" 2>/dev/null | \
        grep -o 'SHA=[^&"<]*' | sort -u | while read host; do
        echo "$category,$host"
    done
done
