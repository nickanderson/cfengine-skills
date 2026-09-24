## Summary

I've created `unhealthy-hosts.sh` that queries the Mission Portal Health page and outputs unhealthy hosts in the format `<category>,<hostkey>`. The script:

- Uses standalone curl (no dependency on the mp-api.sh wrapper)
- Reads credentials from environment variables: `MP_URL`, `MP_USER`, `MP_PASSWORD`
- Skips certificate verification (`-k`) for self-signed certificates
- Queries `/api/health-diagnostic/status` to find all health categories
- Fetches each category's report and extracts hostkeys

**Script:**

```bash
#!/usr/bin/env bash
# Query Mission Portal Health page for unhealthy hosts
# Output: <category>,<hostkey> (one per line)
# Requires: MP_URL, MP_USER, MP_PASSWORD

set -euo pipefail

if [ -z "${MP_URL:-}" ] || [ -z "${MP_USER:-}" ] || [ -z "${MP_PASSWORD:-}" ]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD environment variables required" >&2
    exit 1
fi

mp() {
    local -a body=()
    [ $# -ge 3 ] && body=(-H 'Content-Type: application/json' --data-binary "$3")
    printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
        curl -sS --fail-with-body -k -K - -X "$1" "${body[@]}" "$MP_URL$2"
}

# Get health status to identify all health categories
status=$(mp GET /api/health-diagnostic/status)

# Extract category names (all keys except total and totalFailed)
categories=$(echo "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

# For each category, fetch the report and output category,hostkey
while IFS= read -r category; do
    report=$(mp POST /api/health-diagnostic/report/"$category" '{"limit": 10000}')

    # Extract hostkey (first element of each row) with category prefix
    echo "$report" | jq -r '.data[0].rows[] | "'"$category"'," + .[0]'
done <<< "$categories"
```

**Output:**

```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
hostsUsingSameName,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4
notRecentlyCollected,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4
```