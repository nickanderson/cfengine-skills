#!/bin/bash
set -e

HOSTNAME="${1:?Usage: $0 <hostname>}"
API_URL="${MP_URL%/}/api"
CERT_FILE="${MP_CERT_FILE:-.}"

# Verify environment variables are set
if [[ -z "$MP_URL" || -z "$MP_USER" || -z "$MP_PASSWORD" ]]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD must be set" >&2
    exit 1
fi

# Helper function to make API calls
api_call() {
    local method=$1
    local endpoint=$2
    local data=$3

    local curl_opts=(
        --silent
        --request "$method"
        --user "$MP_USER:$MP_PASSWORD"
        --header "Content-Type: application/json"
    )

    # Handle self-signed certificate
    if [[ ! -f "$CERT_FILE" ]] || [[ "$CERT_FILE" == "." ]]; then
        curl_opts+=(--insecure)
    else
        curl_opts+=(--cacert "$CERT_FILE")
    fi

    if [[ -n "$data" ]]; then
        curl_opts+=(--data "$data")
    fi

    curl "${curl_opts[@]}" "$API_URL$endpoint"
}

# Step 1: Verify host exists
echo "Searching for host: $HOSTNAME"
host_list=$(api_call GET "/hosts?filter=%7B%22hostname%22:%22$HOSTNAME%22%7D")

# Check if host was found
if ! echo "$host_list" | grep -q "$HOSTNAME"; then
    echo "Error: Host '$HOSTNAME' not found in Mission Portal" >&2
    exit 1
fi

# Extract host ID from response
host_id=$(echo "$host_list" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [[ -z "$host_id" ]]; then
    echo "Error: Could not extract host ID for '$HOSTNAME'" >&2
    exit 1
fi

echo "Found host with ID: $host_id"

# Step 2: Delete the host
echo "Removing host from Mission Portal..."
delete_response=$(api_call DELETE "/hosts/$host_id")

# Step 3: Verify deletion - check it's not in active hosts
sleep 1
echo "Verifying host removal..."

active_hosts=$(api_call GET "/hosts?filter=%7B%22hostname%22:%22$HOSTNAME%22%7D" 2>/dev/null || true)

if echo "$active_hosts" | grep -q "$HOSTNAME"; then
    echo "Error: Host still appears in active hosts after deletion attempt" >&2
    exit 1
fi

# Step 4: Verify it's not in deleted hosts either
deleted_hosts=$(api_call GET "/hosts/deleted?filter=%7B%22hostname%22:%22$HOSTNAME%22%7D" 2>/dev/null || true)

if echo "$deleted_hosts" | grep -q "$HOSTNAME"; then
    echo "Error: Host still appears in deleted hosts" >&2
    exit 1
fi

echo "Host '$HOSTNAME' has been completely removed from Mission Portal"
exit 0
