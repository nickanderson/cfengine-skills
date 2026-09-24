#!/usr/bin/env bash
set -euo pipefail

hostname="${1:-}"
if [[ -z "$hostname" ]]; then
    echo "Usage: $0 <hostname>" >&2
    exit 1
fi

# Get credentials from environment
MP_URL="${MP_URL:-}"
MP_USER="${MP_USER:-}"
MP_PASSWORD="${MP_PASSWORD:-}"

if [[ -z "$MP_URL" || -z "$MP_USER" || -z "$MP_PASSWORD" ]]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD environment variables must be set" >&2
    exit 1
fi

# Setup TLS options
tls=(-k)
if [[ -n "${MP_CACERT:-}" ]]; then
    tls=(--cacert "$MP_CACERT")
fi

# Function to make API calls
mp() {
    local method="$1"
    local path="$2"
    local body="${3:-}"

    local -a body_opts=()
    if [[ -n "$body" ]]; then
        body_opts=(-H 'Content-Type: application/json' --data-binary "$body")
    fi

    printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" | \
        curl -sS --fail-with-body "${tls[@]}" -K - -X "$method" "${body_opts[@]}" "$MP_URL$path"
}

# Find the host by hostname using jq to build the JSON properly
query=$(jq -n --arg hostname "$hostname" '{query: "SELECT hostkey FROM hosts WHERE hostname = '\''\($hostname)'\''" }')
response=$(mp POST /api/query "$query")
hostkey=$(echo "$response" | jq -r '.data[0].rows[0][0]')

if [[ -z "$hostkey" || "$hostkey" == "null" ]]; then
    echo "Error: Host '$hostname' not found" >&2
    exit 1
fi

# Delete the host (mark as deleted)
mp DELETE /api/host/"$hostkey" > /dev/null

# Wait for host to appear in deleted hosts list
for i in {1..30}; do
    deleted_response=$(mp GET "/api/hosts/deleted?skip=0&limit=1000")
    deleted=$(echo "$deleted_response" | jq -r "[.data[] | select(.id == \"$hostkey\")] | length")
    if [[ "$deleted" -gt 0 ]]; then
        break
    fi
    sleep 0.5
done

# Permanently delete the host
mp DELETE /api/hosts/delete-permanently/"$hostkey" > /dev/null

# Wait a moment for the deletion to complete
sleep 0.5

# Verify the host is completely gone from active hosts
query=$(jq -n --arg hostname "$hostname" '{query: "SELECT COUNT(*) as count FROM hosts WHERE hostname = '\''\($hostname)'\''" }')
active_response=$(mp POST /api/query "$query")
active_count=$(echo "$active_response" | jq -r '.data[0].rows[0][0]')

# Verify the host is completely gone from deleted hosts
deleted_response=$(mp GET "/api/hosts/deleted?skip=0&limit=1000")
deleted_count=$(echo "$deleted_response" | jq -r "[.data[] | select(.id == \"$hostkey\")] | length")

if [[ "$active_count" != "0" || "$deleted_count" != "0" ]]; then
    echo "Error: Host removal verification failed (active: $active_count, deleted: $deleted_count)" >&2
    exit 1
fi

echo "Host '$hostname' successfully removed"
exit 0
