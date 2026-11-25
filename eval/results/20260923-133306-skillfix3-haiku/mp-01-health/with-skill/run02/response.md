Perfect! The script is now working correctly. Here's the final executable script:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Configuration from environment
MP_URL="${MP_URL:-}"
MP_USER="${MP_USER:-}"
MP_PASSWORD="${MP_PASSWORD:-}"

if [ -z "$MP_URL" ] || [ -z "$MP_USER" ] || [ -z "$MP_PASSWORD" ]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD environment variables are required" >&2
    exit 1
fi

# TLS configuration - skip verification for self-signed cert
TLS_OPTS=(-k)

# Helper function to make API calls
mp_api() {
    local method=$1
    local path=$2
    local data=${3:-}
    
    local curl_opts=(-sS --fail-with-body "${TLS_OPTS[@]}" -X "$method")
    
    if [ -n "$data" ]; then
        curl_opts+=(-H 'Content-Type: application/json' --data-binary "$data")
    fi
    
    # Pass credentials via stdin to avoid them appearing in process list
    printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" | \
        curl "${curl_opts[@]}" -K - "$MP_URL$path"
}

# Get health status to find categories with unhealthy hosts
status=$(mp_api GET /api/health-diagnostic/status)

# Extract categories (keys other than 'total' and 'totalFailed') that have failures
categories=$(echo "$status" | jq -r 'to_entries[] | select(.value > 0 and .key != "total" and .key != "totalFailed") | .key')

# For each category, get the report and print unhealthy hosts
for category in $categories; do
    # Get the report for this category
    report=$(mp_api POST "/api/health-diagnostic/report/$category" '{"limit": 10000}')
    
    # Extract the 'key' field (first column of each row) and print with category
    echo "$report" | jq -r --arg cat "$category" '.data[0].rows[] | "\($cat),\(.[0])"'
done
```

**Output from running against the hub:**

```
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
notRecentlyCollected,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4
hostsUsingSameName,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
hostsUsingSameName,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
```

The script queries the hub's `/api/health-diagnostic/status` endpoint to identify categories with unhealthy hosts, then retrieves the detailed report for each category and outputs one line per flagged host in the requested format. It takes credentials from the `MP_USER`, `MP_PASSWORD`, and `MP_URL` environment variables and skips certificate verification for the self-signed certificate.