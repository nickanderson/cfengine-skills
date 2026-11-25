#!/bin/bash

set -o pipefail

# Script to remove a host from CFEngine Enterprise Mission Portal
# Usage: remove-host.sh <hostname>

if [[ $# -ne 1 ]]; then
    echo "Usage: remove-host.sh <hostname>" >&2
    exit 1
fi

TARGET_HOST="$1"

# Validate required environment variables
if [[ -z "$MP_URL" || -z "$MP_USER" || -z "$MP_PASSWORD" ]]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD environment variables must be set" >&2
    exit 1
fi

# Check if host exists via API
HOST_CHECK=$(curl -s -k -u "$MP_USER:$MP_PASSWORD" \
    -H "Accept: application/vnd.cfengine.enterprise-v1+json" \
    "$MP_URL/api/host/$TARGET_HOST" 2>/dev/null)

if [[ "$HOST_CHECK" == *"Could not find host"* ]]; then
    echo "Error: Host '$TARGET_HOST' not found" >&2
    exit 1
fi

echo "Found host: $TARGET_HOST" >&2

# Delete the host via API
DELETE_RESPONSE=$(curl -s -k -w "\n%{http_code}" -X DELETE \
    -u "$MP_USER:$MP_PASSWORD" \
    -H "Accept: application/vnd.cfengine.enterprise-v1+json" \
    "$MP_URL/api/host/$TARGET_HOST" 2>/dev/null)

HTTP_CODE=$(echo "$DELETE_RESPONSE" | tail -n1)

if [[ "$HTTP_CODE" != "202" && "$HTTP_CODE" != "204" ]]; then
    echo "Error: Failed to delete host (HTTP $HTTP_CODE)" >&2
    exit 1
fi

echo "Delete request accepted (HTTP $HTTP_CODE)" >&2

# Wait for deletion to propagate
sleep 2

# Verify host is no longer accessible via API
API_CHECK=$(curl -s -k -u "$MP_USER:$MP_PASSWORD" \
    -H "Accept: application/vnd.cfengine.enterprise-v1+json" \
    "$MP_URL/api/host/$TARGET_HOST" 2>/dev/null)

if [[ "$API_CHECK" != *"Could not find host"* ]]; then
    echo "Error: Host '$TARGET_HOST' still accessible via API" >&2
    exit 1
fi

echo "Host '$TARGET_HOST' successfully removed"
exit 0
