Perfect! The script is working. Here's the final version and its output:

## Script: `/tmp/cfeval-mp-01-health-with-skill.Nm5XWlA2/work/unhealthy-hosts.sh`

```bash
#!/bin/bash

# Query Mission Portal for unhealthy hosts, print: category,hostkey
# Requires: MP_URL, MP_USER, MP_PASSWORD environment variables

set -euo pipefail

if [[ -z "${MP_URL:-}" || -z "${MP_USER:-}" || -z "${MP_PASSWORD:-}" ]]; then
  echo "Error: MP_URL, MP_USER, MP_PASSWORD environment variables required" >&2
  exit 1
fi

# Function to make authenticated curl requests to MP
mp_api() {
  local method=$1 endpoint=$2 body=${3:-}

  if [[ -n "$body" ]]; then
    curl -sS -k \
      --basic -u "${MP_USER}:${MP_PASSWORD}" \
      -H "Content-Type: application/json" \
      -X "$method" \
      "$MP_URL/api$endpoint" \
      -d "$body"
  else
    curl -sS -k \
      --basic -u "${MP_USER}:${MP_PASSWORD}" \
      -X "$method" \
      "$MP_URL/api$endpoint"
  fi
}

# Get health status to find which categories have unhealthy hosts
status=$(mp_api GET "/health-diagnostic/status")

# Extract category names (all keys except 'total' and 'totalFailed')
categories=$(echo "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

# For each category with unhealthy hosts, fetch and print them
for category in $categories; do
  count=$(echo "$status" | jq ".\"$category\"")
  if [[ "$count" -gt 0 ]]; then
    # Fetch the report for this category, extracting the first column (key/hostkey)
    report=$(mp_api POST "/health-diagnostic/report/$category" '{"limit": 10000}')

    # Extract hostkeys from the first column of rows and print in format: category,hostkey
    echo "$report" | jq -r '.data[0].rows[] | .[0]' | while read -r hostkey; do
      echo "$category,$hostkey"
    done
  fi
done
```

## Output from the hub:

```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
```

The script queries the Mission Portal's `/api/health-diagnostic/status` endpoint to find which categories have unhealthy hosts, then fetches each category's report and extracts the hostkey (first column) from each flagged host.