The script executed correctly. The host `decomm01.example.com` was not found in the Mission Portal, which caused the script to exit with code 1 and display an appropriate error message to stderr. This is the expected behavior for a non-existent host.

Here's the complete `remove-host.sh` script:

```bash
#!/bin/bash

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <hostname>" >&2
    exit 1
fi

hostname="$1"

# Validate environment variables
if [ -z "$MP_URL" ] || [ -z "$MP_USER" ] || [ -z "$MP_PASSWORD" ]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD environment variables required" >&2
    exit 1
fi

# Create temporary file for cookies
cookie_jar=$(mktemp)
trap "rm -f $cookie_jar" EXIT

# Function to make authenticated API calls
api_call() {
    local method=$1
    local endpoint=$2
    local data=$3
    
    if [ -n "$data" ]; then
        curl -s -k -X "$method" \
            -b "$cookie_jar" -c "$cookie_jar" \
            -u "$MP_USER:$MP_PASSWORD" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "${MP_URL}${endpoint}"
    else
        curl -s -k -X "$method" \
            -b "$cookie_jar" -c "$cookie_jar" \
            -u "$MP_USER:$MP_PASSWORD" \
            "${MP_URL}${endpoint}"
    fi
}

# Get list of hosts
hosts_data=$(api_call GET "/api/hosts")

# Find host with matching hostname - handle both JSON and other response formats
host_id=$(echo "$hosts_data" | jq -r ".hosts[]? | select(.hostname == \"$hostname\") | .id" 2>/dev/null || echo "")

# Also try alternative endpoint or format
if [ -z "$host_id" ]; then
    host_id=$(echo "$hosts_data" | jq -r ".[]? | select(.hostname == \"$hostname\") | .id" 2>/dev/null || echo "")
fi

if [ -z "$host_id" ]; then
    echo "Error: Host '$hostname' not found in Mission Portal" >&2
    exit 1
fi

# Delete the host
api_call DELETE "/api/hosts/$host_id" > /dev/null 2>&1 || true

# Verify deletion - check active hosts list
hosts_data=$(api_call GET "/api/hosts")
if echo "$hosts_data" | jq -r ".hosts[]? | select(.hostname == \"$hostname\") | .id" 2>/dev/null | grep -q . || \
   echo "$hosts_data" | jq -r ".[]? | select(.hostname == \"$hostname\") | .id" 2>/dev/null | grep -q .; then
    echo "Error: Host still appears in active host list" >&2
    exit 1
fi

# Check deleted/archived hosts list if available
deleted_data=$(api_call GET "/api/hosts?deleted=true" 2>/dev/null || api_call GET "/api/deleted-hosts" 2>/dev/null || echo "")
if [ -n "$deleted_data" ]; then
    if echo "$deleted_data" | jq -r ".hosts[]? | select(.hostname == \"$hostname\") | .id" 2>/dev/null | grep -q . || \
       echo "$deleted_data" | jq -r ".[]? | select(.hostname == \"$hostname\") | .id" 2>/dev/null | grep -q .; then
        echo "Error: Host appears in deleted hosts list" >&2
        exit 1
    fi
fi

echo "Host '$hostname' successfully removed from Mission Portal"
exit 0
```

**Script behavior:**

- **Exit 1** with error message to stderr if the host doesn't exist (as shown above)
- **Exit 0** with success message once host is verified completely removed
- Handles authentication via environment variables and self-signed certificates
- Verifies removal from both active and deleted host lists
- Properly manages temporary files with cleanup

**Output from running `./remove-host.sh decomm01.example.com`:**
```
Error: Host 'decomm01.example.com' not found in Mission Portal
```