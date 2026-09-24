#!/bin/bash

set -euo pipefail

# Script to remove a host from CFEngine Mission Portal completely
# Usage: remove-host.sh <hostname>

if [[ $# -ne 1 ]]; then
    echo "Usage: remove-host.sh <hostname>" >&2
    exit 1
fi

HOSTNAME="$1"
MP_URL="${MP_URL:-}"
MP_USER="${MP_USER:-}"
MP_PASSWORD="${MP_PASSWORD:-}"

if [[ -z "$MP_URL" || -z "$MP_USER" || -z "$MP_PASSWORD" ]]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD environment variables must be set" >&2
    exit 1
fi

CURL_OPTS=(
    -s
    -k  # Accept self-signed certificates
    -u "$MP_USER:$MP_PASSWORD"
    -H "Content-Type: application/json"
)

# Query Mission Portal for the host to get its ID
HOST_RESPONSE=$(curl "${CURL_OPTS[@]}" "$MP_URL/api/host")

# Find host ID by exact hostname match
HOST_ID=$(echo "$HOST_RESPONSE" | jq -r ".data[] | select(.hostname == \"$HOSTNAME\") | .id" 2>/dev/null | head -1)

if [[ -z "$HOST_ID" || "$HOST_ID" == "null" ]]; then
    echo "Error: Host '$HOSTNAME' not found in Mission Portal" >&2
    exit 1
fi

# Delete the host
DELETE_RESPONSE=$(curl "${CURL_OPTS[@]}" -X DELETE "$MP_URL/api/host/$HOST_ID" 2>&1)

# Check if deletion was successful (no error message)
if echo "$DELETE_RESPONSE" | grep -q "Could not find\|error\|Error" 2>/dev/null; then
    echo "Error: Failed to delete host '$HOSTNAME'" >&2
    exit 1
fi

echo "Host '$HOSTNAME' deleted."

# Verify host is completely gone
sleep 1  # Give the system a moment to process deletion

# Query again to verify deletion
VERIFY_RESPONSE=$(curl "${CURL_OPTS[@]}" "$MP_URL/api/host" 2>/dev/null)

# Check that host no longer exists in the main list
VERIFY_COUNT=$(echo "$VERIFY_RESPONSE" | jq "[.data[] | select(.hostname == \"$HOSTNAME\")] | length" 2>/dev/null)

if [[ "$VERIFY_COUNT" != "0" ]]; then
    echo "Error: Host '$HOSTNAME' still exists after deletion" >&2
    exit 1
fi

# Double-check by trying to fetch the specific host (should return "Could not find host")
SPECIFIC_CHECK=$(curl "${CURL_OPTS[@]}" "$MP_URL/api/host/$HOST_ID" 2>&1)

if ! echo "$SPECIFIC_CHECK" | grep -q "Could not find host" 2>/dev/null; then
    echo "Error: Host '$HOSTNAME' still accessible via ID after deletion" >&2
    exit 1
fi

echo "Host '$HOSTNAME' verified as completely removed from Mission Portal."
exit 0
