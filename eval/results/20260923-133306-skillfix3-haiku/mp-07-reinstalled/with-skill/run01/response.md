Perfect! The script is working correctly. The data shows that `host004.example.com` (192.168.56.6) has two hostkeys—one is the current one (with the most recent report), and the other is a stale record from when the machine was reinstalled.

Here's the complete script:

```bash
#!/usr/bin/env bash
# Find stale host records from reinstalled machines
# Output: <stale hostkey>,<current hostkey>,<hostname>,<ip>

set -euo pipefail

# Verify required environment variables
if [ -z "${MP_URL:-}" ] || [ -z "${MP_USER:-}" ] || [ -z "${MP_PASSWORD:-}" ]; then
  echo "Error: MP_URL, MP_USER, and MP_PASSWORD must be set" >&2
  exit 1
fi

# Set up TLS options
tls=(-k)
if [ -n "${MP_CACERT:-}" ]; then
  tls=(--cacert "$MP_CACERT")
fi

# Query all hosts with their hostkey, hostname, IP, and last report timestamp
query='SELECT hostkey, hostname, ipaddress, lastreporttimestamp FROM hosts ORDER BY hostname, ipaddress, lastreporttimestamp DESC'

# Execute query
response=$(
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
  curl -sS --fail-with-body "${tls[@]}" -K - -X POST \
    -H 'Content-Type: application/json' \
    --data-binary "$(printf '{"query":"%s"}' "$(printf '%s' "$query" | sed 's/"/\\"/g')")" \
    "$MP_URL/api/query"
)

# Extract rows from response
rows=$(echo "$response" | jq -r '.data[0].rows[] | @csv' 2>/dev/null)

# Process rows to find stale records
declare -A seen
while IFS=',' read -r hostkey hostname ipaddress lastreport; do
  # Remove quotes added by @csv
  hostkey="${hostkey%\"}"
  hostkey="${hostkey#\"}"
  hostname="${hostname%\"}"
  hostname="${hostname#\"}"
  ipaddress="${ipaddress%\"}"
  ipaddress="${ipaddress#\"}"
  
  # Create key for grouping: hostname+ipaddress
  key="$hostname|$ipaddress"
  
  if [ -z "${seen[$key]:-}" ]; then
    # First occurrence is the current one (most recent due to ORDER BY DESC)
    seen[$key]="$hostkey"
  else
    # This is a stale record
    current_hostkey="${seen[$key]}"
    echo "$hostkey,$current_hostkey,$hostname,$ipaddress"
  fi
done <<< "$rows"
```

**Output from your hub:**

```
SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5,host004.example.com,192.168.56.6
```

This shows one stale record: `host004.example.com` was reinstalled and now reports under a new hostkey, but the old record is still in the database. The script requires `MP_URL`, `MP_USER`, and `MP_PASSWORD` environment variables; it optionally accepts `MP_CACERT` to verify the hub's certificate (the `-k` flag skips verification by default for self-signed certs).