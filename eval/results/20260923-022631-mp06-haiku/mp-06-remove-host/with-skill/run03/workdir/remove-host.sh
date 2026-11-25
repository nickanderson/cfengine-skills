#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <hostname>" >&2
    exit 1
fi

hostname="$1"

# Get credentials from environment or use defaults
MP_URL="${MP_URL:-https://192.168.56.2}"
MP_USER="${MP_USER:-admin}"
MP_PASSWORD="${MP_PASSWORD:?MP_PASSWORD must be set}"

# Create a netrc file for curl authentication
netrc_file=$(mktemp)
trap "rm -f '$netrc_file'" EXIT

{
    # Extract hostname from URL (remove https://)
    mp_host="${MP_URL#https://}"
    mp_host="${mp_host#http://}"
    mp_host="${mp_host%/}"
    printf 'machine %s login %s password %s\n' "$mp_host" "$MP_USER" "$MP_PASSWORD"
} > "$netrc_file"
chmod 600 "$netrc_file"

curl_opts=(-sS --netrc-file "$netrc_file" -k)

# Find host by hostname
echo "Finding host: $hostname" >&2

# Query to find all hosts (page through if needed)
page=1
hostkey=""
while [[ -z "$hostkey" ]]; do
    response=$(curl "${curl_opts[@]}" "$MP_URL/api/host?page=$page&count=500")
    hostkey=$(echo "$response" | jq -r ".data[] | select(.hostname == \"$hostname\") | .id" 2>/dev/null || echo "")

    total=$(echo "$response" | jq -r ".meta.total // 0")
    count=$(echo "$response" | jq -r ".meta.count // 0")

    if [[ -z "$hostkey" ]]; then
        # Check if there are more pages
        if (( (page * 500) >= total )); then
            break
        fi
        ((page++))
    fi
done

if [[ -z "$hostkey" ]]; then
    echo "Error: Host '$hostname' not found" >&2
    exit 1
fi

echo "Found host with key: $hostkey" >&2

# Delete the host
echo "Deleting host: $hostname" >&2
http_status=$(curl "${curl_opts[@]}" -w "%{http_code}" -o /dev/null -X DELETE "$MP_URL/api/host/$hostkey")

if [[ ! "$http_status" =~ ^(202|204)$ ]]; then
    echo "Error: Failed to delete host (HTTP $http_status)" >&2
    exit 1
fi
echo "Host deletion initiated (HTTP $http_status)" >&2

# Verify host is gone completely (from both active and deleted lists)
echo "Verifying host is removed from all locations" >&2
max_attempts=30
attempt=0

while (( attempt < max_attempts )); do
    ((attempt++))

    # Check if in active hosts
    verify_response=$(curl "${curl_opts[@]}" "$MP_URL/api/host?page=1&count=500")
    in_active=$(echo "$verify_response" | jq -r ".data[] | select(.hostname == \"$hostname\") | .id" 2>/dev/null || echo "")

    # Check if in deleted hosts
    deleted_response=$(curl "${curl_opts[@]}" "$MP_URL/api/hosts/deleted?skip=0&limit=500")
    in_deleted=$(echo "$deleted_response" | jq -r ".data[] | select(.id == \"$hostkey\") | .id" 2>/dev/null || echo "")

    if [[ -z "$in_active" ]] && [[ -z "$in_deleted" ]]; then
        echo "Verified: Host completely removed from all locations" >&2
        echo "Successfully removed host: $hostname" >&2
        exit 0
    fi

    if [[ -n "$in_active" ]]; then
        echo "Host still in active list, waiting..." >&2
    fi
    if [[ -n "$in_deleted" ]]; then
        echo "Host still in deleted list, waiting..." >&2
    fi

    if (( attempt < max_attempts )); then
        sleep 1
    fi
done

echo "Error: Host still exists after $max_attempts verification attempts" >&2
exit 1
