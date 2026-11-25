Perfect! The script works correctly. Here's the final script:

```bash
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
```

**Output from running against the hub:**

```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
```

The script queries the Mission Portal Health page diagnostics API, identifies each category with flagged hosts, retrieves the detailed report for each category, and outputs one line per unhealthy host with its health category and hostkey.