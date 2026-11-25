#!/bin/bash

set -euo pipefail

# Script to remove a host from CFEngine Enterprise Mission Portal
# Removes host completely from both active and deleted host lists

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <hostname>" >&2
    exit 1
fi

HOSTNAME="$1"

# Validate required environment variables
if [[ -z "${MP_URL:-}" || -z "${MP_USER:-}" || -z "${MP_PASSWORD:-}" ]]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD environment variables must be set" >&2
    exit 1
fi

# Create temporary directory for API responses
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Make authenticated API call
api_call() {
    local method="$1"
    local endpoint="$2"
    local output_file="$3"

    local url="${MP_URL}${endpoint}"

    curl -X "$method" \
        -k \
        --silent \
        --show-error \
        -u "${MP_USER}:${MP_PASSWORD}" \
        -w "%{http_code}" \
        -o "$output_file" \
        "$url"
}

# Step 1: Verify host exists in the system
echo "Verifying host '$HOSTNAME' exists..." >&2
hosts_file="$TEMP_DIR/hosts_initial.json"
http_code=$(api_call GET "/api/host" "$hosts_file")

if [[ "$http_code" != "200" ]]; then
    echo "Error: Failed to retrieve host list (HTTP $http_code)" >&2
    exit 1
fi

# Extract all host IDs for this hostname (there may be multiple entries)
host_ids=$(grep -n "\"hostname\"[ ]*:[ ]*\"${HOSTNAME}\"" "$hosts_file" || true | cut -d: -f1 | while read line_num; do
    sed -n "${line_num},$((line_num+5))p" "$hosts_file" | grep '"id"' | head -1 | grep -o 'SHA=[^"]*'
done || true)

if [[ -z "$host_ids" ]]; then
    echo "Error: Host '$HOSTNAME' not found" >&2
    exit 1
fi

echo "Host found, initiating removal of all instances..." >&2

# Step 2: Delete all instances of this host via API
delete_count=0
while IFS= read -r host_id; do
    if [[ -n "$host_id" ]]; then
        echo "Removing host instance (ID: $host_id)..." >&2
        delete_response="$TEMP_DIR/delete_response_${host_id}.json"
        http_code=$(api_call DELETE "/api/host/$host_id" "$delete_response")

        if [[ "$http_code" != "200" && "$http_code" != "204" && "$http_code" != "202" ]]; then
            echo "Error: Host deletion failed (HTTP $http_code)" >&2
            if [[ -f "$delete_response" && -s "$delete_response" ]]; then
                cat "$delete_response" >&2
            fi
            exit 1
        fi
        ((delete_count++))
    fi
done <<< "$host_ids"

echo "Deleted $delete_count instance(s)" >&2

# Step 3: Wait briefly for API processing
sleep 1

# Step 4: Verify host is no longer in active hosts list
echo "Verifying complete removal..." >&2
hosts_verify="$TEMP_DIR/hosts_verify.json"
http_code=$(api_call GET "/api/host" "$hosts_verify")

if [[ "$http_code" != "200" ]]; then
    echo "Error: Failed to verify host removal (HTTP $http_code)" >&2
    exit 1
fi

if grep -q "\"hostname\"[ ]*:[ ]*\"${HOSTNAME}\"" "$hosts_verify"; then
    echo "Error: Host still present in active hosts list" >&2
    exit 1
fi

echo "Host '$HOSTNAME' successfully removed from Mission Portal" >&2
exit 0
