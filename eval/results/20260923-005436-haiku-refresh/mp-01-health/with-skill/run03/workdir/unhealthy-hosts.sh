#!/bin/bash
set -e

MP_URL="${MP_URL:-https://192.168.56.2}"
MP_USER="${MP_USER:-admin}"
MP_PASSWORD="${MP_PASSWORD}"
MP_CACERT="${MP_CACERT}"

if [ -z "$MP_PASSWORD" ]; then
    echo "Error: MP_PASSWORD environment variable not set" >&2
    exit 1
fi

# Build curl config to avoid showing password in process list
curl_config=$(mktemp)
trap "rm -f $curl_config" EXIT

printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" > "$curl_config"

if [ -n "$MP_CACERT" ]; then
    echo "cacert = \"$MP_CACERT\"" >> "$curl_config"
else
    echo "insecure" >> "$curl_config"
fi

# Helper to make API calls
api() {
    local method="$1"
    local path="$2"
    local data="${3}"

    if [ -z "$data" ]; then
        curl -sS -X "$method" -K "$curl_config" "$MP_URL$path"
    else
        curl -sS -X "$method" -H "Content-Type: application/json" -d "$data" -K "$curl_config" "$MP_URL$path"
    fi
}

# Get health status to identify flagged categories
status=$(api GET /api/health-diagnostic/status)

# For each category with flagged hosts, get the report
while IFS= read -r category; do
    count=$(echo "$status" | jq ".\"$category\"")

    if [ "$count" -gt 0 ]; then
        # Query the report for this category and extract hostkeys
        # Hostkey is the first element of each row array in data[0].rows
        report=$(api POST "/api/health-diagnostic/report/$category" '{"limit": 10000}')
        echo "$report" | jq -r '.data[0].rows[] | "'"$category"'," + .[0]'
    fi
done < <(echo "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')
