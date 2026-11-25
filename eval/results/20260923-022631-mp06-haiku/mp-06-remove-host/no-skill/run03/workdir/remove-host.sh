#!/bin/bash

# Remove a host from CFEngine Enterprise Mission Portal completely
# Usage: remove-host.sh <hostname>
# Exit codes: 0 = success, 1 = host not found or removal failed

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <hostname>" >&2
    exit 1
fi

HOSTNAME="$1"

# Validate required environment variables
if [[ -z "$MP_URL" ]] || [[ -z "$MP_USER" ]] || [[ -z "$MP_PASSWORD" ]]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD environment variables must be set" >&2
    exit 1
fi

# curl options for self-signed certificate and basic auth
CURL_OPTS=(-k -s -u "$MP_USER:$MP_PASSWORD")

# Step 1: Verify the host exists and get its ID
echo "Verifying host '$HOSTNAME' exists..."
HOST_LIST=$(curl "${CURL_OPTS[@]}" "$MP_URL/api/host")

# Extract the host ID for the exact hostname match using Python for proper JSON parsing
HOST_ID=$(echo "$HOST_LIST" | python3 -c "import sys, json; data = json.load(sys.stdin); host = next((h for h in data.get('data', []) if h['hostname'] == '$HOSTNAME'), None); print(host['id'] if host else '')" 2>/dev/null)

if [[ -z "$HOST_ID" ]]; then
    echo "Error: Host '$HOSTNAME' not found in Mission Portal" >&2
    exit 1
fi

echo "Host found with ID: $HOST_ID. Deleting..."

# Step 2: Delete the host via API using its ID
DELETE_RESPONSE=$(curl "${CURL_OPTS[@]}" -w "\n%{http_code}" -X DELETE "$MP_URL/api/host/$HOST_ID")
HTTP_CODE=$(echo "$DELETE_RESPONSE" | tail -1)
DELETE_BODY=$(echo "$DELETE_RESPONSE" | head -n -1)

# Check for successful deletion (202 Accepted or 200 OK)
if [[ "$HTTP_CODE" != "202" ]] && [[ "$HTTP_CODE" != "200" ]]; then
    echo "Error: Failed to delete host '$HOSTNAME' (HTTP $HTTP_CODE)" >&2
    if [[ -n "$DELETE_BODY" ]]; then
        echo "$DELETE_BODY" >&2
    fi
    exit 1
fi

# Step 3: Verify complete removal from active hosts
echo "Verifying removal from active hosts list..."
sleep 2

ACTIVE_HOSTS=$(curl "${CURL_OPTS[@]}" "$MP_URL/api/host")

# Check if hostname still exists
if echo "$ACTIVE_HOSTS" | grep -F "\"hostname\"" | grep -F "\"$HOSTNAME\"" >/dev/null 2>&1; then
    echo "Error: Host '$HOSTNAME' still appears in active hosts list" >&2
    exit 1
fi

echo "Success: Host '$HOSTNAME' has been completely removed from Mission Portal"
exit 0
