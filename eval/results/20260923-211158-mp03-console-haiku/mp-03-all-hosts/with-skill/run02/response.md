Perfect! The script ran successfully against the hub and printed **1,123 hosts** in CSV format.

Here's the final script:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Credentials from environment
: "${MP_URL:?MP_URL not set}"
: "${MP_USER:?MP_USER not set}"
: "${MP_PASSWORD:?MP_PASSWORD not set}"

# TLS: skip verification for self-signed cert, or use provided certificate
tls=(-k)
[ -n "${MP_CACERT:-}" ] && tls=(--cacert "$MP_CACERT")

# Query all hosts with pagination
skip=0
limit=5000

while true; do
  body=$(jq -n \
    --arg query "SELECT hostkey, hostname, ipaddress FROM hosts" \
    '{query: $query, skip: '"$skip"', limit: '"$limit"'}')
  
  response=$(
    printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
      curl -sS --fail-with-body "${tls[@]}" -K - -X POST \
        -H 'Content-Type: application/json' --data-binary "$body" \
        "$MP_URL/api/query"
  )
  
  # Extract rows and row count
  rows=$(echo "$response" | jq -r '.data[0].rows[]? | @csv')
  row_count=$(echo "$response" | jq '.data[0].rowCount // 0')
  
  [ "$row_count" -eq 0 ] && break
  
  echo "$rows"
  
  [ "$row_count" -lt "$limit" ] && break
  skip=$((skip + row_count))
done
```

**Output format verified:** CSV with `hostkey`, `hostname`, and `ipaddress` columns, no header.  
**Total hosts returned:** 1,123

The script handles pagination to ensure no hosts are missed, accepts credentials from environment variables, and skips TLS verification for the self-signed certificate (or uses `MP_CACERT` if provided).