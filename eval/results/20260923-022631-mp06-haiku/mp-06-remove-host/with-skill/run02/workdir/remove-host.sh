#!/bin/bash
set -eu

usage() {
    echo "Usage: $0 <hostname>" >&2
    exit 1
}

[[ $# -eq 1 ]] || usage

hostname="$1"
MP_URL="${MP_URL:?MP_URL not set}"
MP_USER="${MP_USER:?MP_USER not set}"
MP_PASSWORD="${MP_PASSWORD:?MP_PASSWORD not set}"

# Create a temp file for curl config
curl_config=$(mktemp)
trap 'rm -f "$curl_config"' EXIT

# Write credentials to curl config
write_curl_config() {
    cat > "$curl_config" <<EOF
user = "$MP_USER:$MP_PASSWORD"
EOF
}

# Find host by hostname using SQL query
find_host() {
    local name="$1"
    write_curl_config

    local query="SELECT hostkey, hostname FROM hosts WHERE hostname = '$name'"

    local response
    response=$(curl -sS -k --config "$curl_config" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"$query\"}" \
        "$MP_URL/api/query")

    local hostkey
    hostkey=$(echo "$response" | jq -r '.data[0].rows[0][0]?' 2>/dev/null)

    if [[ -z "$hostkey" || "$hostkey" == "null" ]]; then
        return 1
    fi

    echo "$hostkey"
}

# Check if host exists in active hosts
host_exists_in_active() {
    local hostkey="$1"
    write_curl_config

    local http_code
    http_code=$(curl -sS -k --config "$curl_config" \
        --write-out "%{http_code}" -o /dev/null \
        -X GET "$MP_URL/api/host/$hostkey")

    [[ "$http_code" == "200" ]]
}

# Check if host exists in deleted hosts
host_exists_in_deleted() {
    local hostkey="$1"
    write_curl_config

    local response
    response=$(curl -sS -k --config "$curl_config" \
        -X POST \
        -H "Content-Type: application/json" \
        -d '{"limit": 10000}' \
        "$MP_URL/api/health-diagnostic/report/deletedHostsReport")

    # Check if the hostkey appears in the deleted hosts array
    echo "$response" | jq -e ".[] | select(.[0] == \"$hostkey\")" >/dev/null 2>&1
}

# Main logic
echo "Removing host: $hostname"

# Find the host
if ! hostkey=$(find_host "$hostname"); then
    echo "Error: Host '$hostname' not found" >&2
    exit 1
fi

echo "Found host with key: $hostkey"

# Delete the host
echo "Deleting host from Mission Portal..."
write_curl_config

http_code=$(curl -sS -k --config "$curl_config" \
    --write-out "%{http_code}" -o /dev/null \
    -X DELETE "$MP_URL/api/host/$hostkey")

if [[ "$http_code" != "204" ]] && [[ "$http_code" != "200" ]] && [[ "$http_code" != "202" ]]; then
    echo "Error: Failed to delete host (HTTP $http_code)" >&2
    exit 1
fi

echo "Delete request sent (HTTP $http_code)"

# Verify deletion - wait a moment for the operation to complete
echo "Waiting for deletion to complete..."
sleep 3

# Verify host is gone from active hosts
verify_count=0
while [[ $verify_count -lt 3 ]]; do
    if ! host_exists_in_active "$hostkey"; then
        echo "Verified: Host removed from active host list"
        break
    fi
    ((verify_count++))
    if [[ $verify_count -lt 3 ]]; then
        echo "  Host still in active list, checking again..."
        sleep 2
    fi
done

if [[ $verify_count -eq 3 ]]; then
    echo "Error: Host still exists in active host list after deletion" >&2
    exit 1
fi

# Verify host is gone from deleted hosts
if host_exists_in_deleted "$hostkey"; then
    echo "Error: Host still appears in deleted hosts list" >&2
    exit 1
fi
echo "Verified: Host removed from deleted hosts list"

echo "Success: Host '$hostname' has been completely removed from Mission Portal"
exit 0
