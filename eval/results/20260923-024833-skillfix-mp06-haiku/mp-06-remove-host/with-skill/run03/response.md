## Summary

I've created the `remove-host.sh` script that completely removes a host from CFEngine Enterprise Mission Portal. The script:

1. **Validates the hostname** - takes exactly one argument, exits with error if missing
2. **Finds the host** - queries the reporting database for the hostname, exits with error if not found
3. **Removes the host** - executes a two-step deletion:
   - First call: `DELETE /api/host/:hostkey` marks it as deleted
   - Wait and poll until it appears in the deleted hosts list
   - Second call: `DELETE /api/hosts/delete-permanently/:hostkey` removes the record permanently
4. **Verifies complete removal** - confirms the host is gone from both active and deleted host lists
5. **Reports status** - exits 0 with success message, or exits 1 with error

The script uses:
- Environment variables for credentials: `MP_URL`, `MP_USER`, `MP_PASSWORD`
- Optional `MP_CACERT` for certificate verification (defaults to `-k` for self-signed)
- Safe credential handling via stdin (never in command line)
- `jq` for proper JSON construction and parsing

## Execution Results

**decomm01.example.com removal:**
```
Host 'decomm01.example.com' successfully removed
```
✓ Exit code: 0

**Verification:**
- Active hosts count: 0
- Deleted hosts count: 0

**Error handling demonstration** (non-existent host):
```
Error: Host 'nonexistent.example.com' not found
```
✓ Exit code: 1

## Complete Script

```bash
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
```