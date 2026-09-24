Perfect! I've created the `stale-records.sh` script and run it against your CFEngine hub. Here are the results:

## Stale Records Found

```
SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5,host004.example.com,192.168.56.6
SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940,hub.example.com,192.168.56.5
```

**What this means:**
- **host004.example.com** (192.168.56.6): The old hostkey `SHA=714...` should be deleted. The machine is now reporting under `SHA=067...`
- **hub.example.com** (192.168.56.5): The old hostkey `SHA=f20...` should be deleted. The hub is now reporting under `SHA=6bb...`

## The Script

```bash
#!/usr/bin/env bash

set -euo pipefail

# Validate required environment variables
for var in MP_URL MP_USER MP_PASSWORD; do
  if [ -z "${!var:-}" ]; then
    echo "Error: $var not set" >&2
    exit 1
  fi
done

# Use insecure TLS by default (self-signed cert), allow override with MP_CACERT
tls=(-k)
if [ -n "${MP_CACERT:-}" ]; then
  tls=(--cacert "$MP_CACERT")
fi

# Helper function to call Mission Portal API
mp() {
  local -a body=()
  [ $# -ge 3 ] && body=(-H 'Content-Type: application/json' --data-binary "$3")
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
    curl -sS --fail-with-body "${tls[@]}" -K - -X "$1" "${body[@]}" "$MP_URL$2"
}

# Query all hosts with agent status to determine which is currently active
# Use agent execution timestamp as the primary indicator of activity
query='SELECT h.hostkey, h.hostname, h.ipaddress, h.lastreporttimestamp, a.lastagentlocalexecutiontimestamp FROM hosts h LEFT JOIN agentstatus a ON h.hostkey = a.hostkey ORDER BY h.hostname, COALESCE(a.lastagentlocalexecutiontimestamp, h.lastreporttimestamp) DESC'

result=$(mp POST /api/query "{\"query\": \"$query\"}")

# Parse the result with jq to find stale records
# Group by hostname, find duplicates, and output stale entries
echo "$result" | jq -r '
  .data[0].rows as $rows |
  
  # Group rows by hostname (field 1)
  ($rows | group_by(.[1])) as $groups |
  
  # Process only groups with multiple entries (duplicate hostnames)
  $groups[] |
  select(length > 1) |
  
  # For each duplicate group, the first entry (after sorting by timestamp DESC) is current
  # All others are stale
  . as $group |
  ($group[0][0]) as $current_hostkey |
  ($group[0][1]) as $hostname |
  
  # Output each stale record
  $group[1:] |
  .[] |
  "\(.[0]),\($current_hostkey),\($hostname),\(.[2])"
'

exit 0
```

**To use the script:**
Set environment variables and run:
```bash
export MP_URL="https://your-hub-ip"
export MP_USER="admin"
export MP_PASSWORD="your-password"
export MP_CACERT="/path/to/cert.pem"  # optional, for certificate verification

./stale-records.sh
```

The script requires curl, jq, and bash. It skips certificate verification by default (`-k`) since your hub has a self-signed certificate — provide `MP_CACERT` to verify it instead.