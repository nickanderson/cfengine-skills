## Summary

I've created `all-hosts.sh` and tested it against your Mission Portal hub. Here's what it does:

**Script features:**
- Takes credentials from environment variables: `MP_URL`, `MP_USER`, `MP_PASSWORD`
- Supports optional `MP_CACERT` for certificate verification; defaults to `-k` (skip verification for self-signed)
- Queries the Mission Portal `/api/query` endpoint for all hosts
- Outputs one CSV line per host: `hostkey,hostname,ipaddress`
- No header, only data—ready for CMDB ingestion

**Test results:**
- ✅ Script executed successfully
- ✅ **1123 hosts** returned
- ✅ Output is properly formatted CSV with quoted fields

```bash
#!/usr/bin/env bash
# Query CFEngine Mission Portal for all hosts; output CSV: hostkey,hostname,ipaddress
set -euo pipefail

# Credentials and URL from environment
: "${MP_URL:?Missing MP_URL}"
: "${MP_USER:?Missing MP_USER}"
: "${MP_PASSWORD:?Missing MP_PASSWORD}"

# TLS options: skip verification by default (self-signed), or use supplied certificate
tls=(-k)
[ -n "${MP_CACERT:-}" ] && tls=(--cacert "$MP_CACERT")

# Extract hostname from URL for netrc
host="${MP_URL#https://}"
host="${host#http://}"
host="${host%%/*}"

# Query the hosts view for all hosts
query='SELECT hostkey, hostname, ipaddress FROM hosts'

# Make the API call; print response body on success, exit nonzero on failure
response=$(curl -sS --fail-with-body "${tls[@]}" \
  --netrc-file <(printf 'machine %s login %s password %s\n' "$host" "$MP_USER" "$MP_PASSWORD") \
  -H 'Content-Type: application/json' \
  -d "{\"query\": \"$query\"}" \
  "$MP_URL/api/query")

# Extract rows from the JSON response and output as CSV
# Response structure: {"data": [{"header": [...], "rows": [[...], ...], "rowCount": N}]}
printf '%s\n' "$response" | jq -r '.data[0].rows[] | @csv'
```

The script is ready to use. It requires `jq` for JSON parsing and will work with the environment variables you already have set.