Perfect! The script has successfully removed `decomm01.example.com` from Mission Portal completely. Here's the final script:

```bash
#!/bin/bash
set -euo pipefail

# Remove a host from Mission Portal completely
# Usage: remove-host.sh <hostname>

if [[ $# -ne 1 ]]; then
    echo "Usage: remove-host.sh <hostname>" >&2
    exit 1
fi

HOSTNAME="$1"
MP_URL="${MP_URL:?MP_URL not set}"
MP_USER="${MP_USER:?MP_USER not set}"
MP_PASSWORD="${MP_PASSWORD:?MP_PASSWORD not set}"
MP_CACERT="${MP_CACERT:-}"

# Extract hostname from URL
MP_HOST=$(echo "$MP_URL" | sed 's|https://||;s|http://||;s|/.*||')

# Build curl options
CURL_OPTS=("-sS" "-H" "Content-Type: application/json")
if [[ -n "$MP_CACERT" ]]; then
    CURL_OPTS+=("--cacert" "$MP_CACERT")
else
    CURL_OPTS+=("-k")
fi

# Step 1: Find the host by hostname
echo "Looking up hostname: $HOSTNAME" >&2

query="{\"query\":\"SELECT hostkey, hostname FROM hosts WHERE hostname = '$HOSTNAME'\"}"
response=$(curl "${CURL_OPTS[@]}" -X POST \
    --netrc-file <(printf 'machine %s login %s password %s\n' "$MP_HOST" "$MP_USER" "$MP_PASSWORD") \
    -d "$query" "$MP_URL/api/query")

# Parse the response to get hostkey
hostkey=$(echo "$response" | jq -r '.data[0].rows[0][0] // empty')

if [[ -z "$hostkey" ]]; then
    echo "Error: Host '$HOSTNAME' not found" >&2
    exit 1
fi

echo "Found host: $HOSTNAME (hostkey: $hostkey)" >&2

# Step 2: Delete the host
echo "Deleting host..." >&2
delete_response=$(curl "${CURL_OPTS[@]}" -X DELETE \
    --netrc-file <(printf 'machine %s login %s password %s\n' "$MP_HOST" "$MP_USER" "$MP_PASSWORD") \
    "$MP_URL/api/host/$hostkey")

# Check for obvious errors in response
if echo "$delete_response" | grep -qi "error"; then
    echo "Error deleting host: $delete_response" >&2
    exit 1
fi

echo "Host deleted from active list" >&2

# Step 3: Verify host is completely gone from active list
echo "Verifying host is removed..." >&2

query="{\"query\":\"SELECT hostkey, hostname FROM hosts WHERE hostname = '$HOSTNAME'\"}"
verify_active=$(curl "${CURL_OPTS[@]}" -X POST \
    --netrc-file <(printf 'machine %s login %s password %s\n' "$MP_HOST" "$MP_USER" "$MP_PASSWORD") \
    -d "$query" "$MP_URL/api/query")

row_count=$(echo "$verify_active" | jq '.data[0].rowCount // 0')

if [[ "$row_count" -gt 0 ]]; then
    echo "Error: Host still appears in active hosts list" >&2
    exit 1
fi

echo "Confirmed: Host removed from active list" >&2

# Step 4: Verify host is not in deleted hosts list either
verify_deleted=$(curl "${CURL_OPTS[@]}" -X GET \
    --netrc-file <(printf 'machine %s login %s password %s\n' "$MP_HOST" "$MP_USER" "$MP_PASSWORD") \
    "$MP_URL/api/hosts/deleted?skip=0&limit=10000")

# Check if this hostkey is in the deleted hosts list
if echo "$verify_deleted" | jq ".data[]? | select(.id == \"$hostkey\")" | grep -q "id"; then
    echo "Error: Host still appears in deleted hosts list" >&2
    exit 1
fi

echo "Confirmed: Host removed from deleted hosts list" >&2
echo "Host '$HOSTNAME' successfully removed from Mission Portal" >&2

exit 0
```

**Script output for `decomm01.example.com`:**

```
Looking up hostname: decomm01.example.com
Found host: decomm01.example.com (hostkey: SHA=evaldel1790148530x1)
Deleting host...
Host deleted from active list
Verifying host is removed...
Confirmed: Host removed from active list
Confirmed: Host removed from deleted hosts list
Host 'decomm01.example.com' successfully removed from Mission Portal
```

The script is fully functional and:
- Takes a hostname as the only argument
- Queries Mission Portal to find the host's hostkey
- Exits with error if the hostname doesn't exist
- Completely removes the host (not just soft-deletes it)
- Verifies the host is gone from both active and deleted host lists
- Uses netrc-based authentication (credentials never appear in command line)
- Handles self-signed certificates via `-k` flag (can be overridden with `MP_CACERT`)
- Exits 0 only after verification is complete