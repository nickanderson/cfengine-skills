Excellent! The script is complete and working. Here's the final solution:

## unhealthy-hosts.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

# Requires: MP_URL, MP_USER, MP_PASSWORD
# Optional: MP_CACERT (path to hub's certificate; if not provided, skips verification)

MP_URL="${MP_URL:?MP_URL environment variable not set}"
MP_USER="${MP_USER:?MP_USER environment variable not set}"
MP_PASSWORD="${MP_PASSWORD:?MP_PASSWORD environment variable not set}"

# TLS options: use provided certificate or skip verification for self-signed
if [ -n "${MP_CACERT:-}" ]; then
    TLS_OPTS=(--cacert "$MP_CACERT")
else
    TLS_OPTS=(-k)
fi

# Helper to call Mission Portal API
mp_api() {
    local method="$1"
    local path="$2"
    local body="${3:-}"
    
    local -a opts=(
        -sS --fail-with-body
        "${TLS_OPTS[@]}"
        -X "$method"
    )
    
    if [ -n "$body" ]; then
        opts+=(-H 'Content-Type: application/json' --data-binary "$body")
    fi
    
    # Basic auth via Authorization header
    local auth
    auth=$(printf '%s:%s' "$MP_USER" "$MP_PASSWORD" | base64 -w0)
    opts+=(-H "Authorization: Basic $auth")
    
    curl "${opts[@]}" "$MP_URL$path"
}

# Get all health diagnostic categories
status=$(mp_api GET '/api/health-diagnostic/status')

# Extract category names, excluding metadata fields
categories=$(echo "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

# Query each category and output hostkeys
for category in $categories; do
    report=$(mp_api POST "/api/health-diagnostic/report/$category" '{"limit": 10000}')
    
    # Extract hostkey (first element of each row) and output category,hostkey
    echo "$report" | jq -r '.data[0].rows[] | .[0]' | while read -r hostkey; do
        [ -n "$hostkey" ] && echo "$category,$hostkey"
    done
done
```

## Output from running against the hub:

```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
hostsUsingSameName,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4
notRecentlyCollected,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4
```

The script queries the Mission Portal's Health Diagnostics API (`/api/health-diagnostic/status`) to discover all health problem categories, then fetches the list of flagged hosts for each category using `/api/health-diagnostic/report/{category}`. It outputs one line per host with the format `<category>,<hostkey>`, with nothing else on stdout. Credentials are passed via environment variables (MP_URL, MP_USER, MP_PASSWORD) with optional certificate verification via MP_CACERT; it skips verification by default for self-signed hubs.