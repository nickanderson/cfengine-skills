#!/bin/bash

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <hostname>" >&2
    exit 1
fi

hostname="$1"

# Validate environment variables
if [ -z "$MP_URL" ] || [ -z "$MP_USER" ] || [ -z "$MP_PASSWORD" ]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD environment variables required" >&2
    exit 1
fi

# Create temporary file for cookies
cookie_jar=$(mktemp)
trap "rm -f $cookie_jar" EXIT

# Function to make authenticated API calls
api_call() {
    local method=$1
    local endpoint=$2
    local data=$3

    if [ -n "$data" ]; then
        curl -s -k -X "$method" \
            -b "$cookie_jar" -c "$cookie_jar" \
            -u "$MP_USER:$MP_PASSWORD" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "${MP_URL}${endpoint}"
    else
        curl -s -k -X "$method" \
            -b "$cookie_jar" -c "$cookie_jar" \
            -u "$MP_USER:$MP_PASSWORD" \
            "${MP_URL}${endpoint}"
    fi
}

# Get list of hosts
hosts_data=$(api_call GET "/api/hosts")

# Find host with matching hostname - handle both JSON and other response formats
host_id=$(echo "$hosts_data" | jq -r ".hosts[]? | select(.hostname == \"$hostname\") | .id" 2>/dev/null || echo "")

# Also try alternative endpoint or format
if [ -z "$host_id" ]; then
    host_id=$(echo "$hosts_data" | jq -r ".[]? | select(.hostname == \"$hostname\") | .id" 2>/dev/null || echo "")
fi

if [ -z "$host_id" ]; then
    echo "Error: Host '$hostname' not found in Mission Portal" >&2
    exit 1
fi

# Delete the host
api_call DELETE "/api/hosts/$host_id" > /dev/null 2>&1 || true

# Verify deletion - check active hosts list
hosts_data=$(api_call GET "/api/hosts")
if echo "$hosts_data" | jq -r ".hosts[]? | select(.hostname == \"$hostname\") | .id" 2>/dev/null | grep -q . || \
   echo "$hosts_data" | jq -r ".[]? | select(.hostname == \"$hostname\") | .id" 2>/dev/null | grep -q .; then
    echo "Error: Host still appears in active host list" >&2
    exit 1
fi

# Check deleted/archived hosts list if available
deleted_data=$(api_call GET "/api/hosts?deleted=true" 2>/dev/null || api_call GET "/api/deleted-hosts" 2>/dev/null || echo "")
if [ -n "$deleted_data" ]; then
    if echo "$deleted_data" | jq -r ".hosts[]? | select(.hostname == \"$hostname\") | .id" 2>/dev/null | grep -q . || \
       echo "$deleted_data" | jq -r ".[]? | select(.hostname == \"$hostname\") | .id" 2>/dev/null | grep -q .; then
        echo "Error: Host appears in deleted hosts list" >&2
        exit 1
    fi
fi

echo "Host '$hostname' successfully removed from Mission Portal"
exit 0
