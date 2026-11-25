Perfect! The script is now working correctly. Here's the final executable script and its output against the hub:

## Script: unhealthy-hosts.sh

```bash
#!/bin/bash
set -euo pipefail

# Credentials from environment
MP_URL="${MP_URL:?MP_URL not set}"
MP_USER="${MP_USER:?MP_USER not set}"
MP_PASSWORD="${MP_PASSWORD:?MP_PASSWORD not set}"

# Create temporary netrc file
NETRC=$(mktemp)
trap "rm -f $NETRC" EXIT
printf 'machine %s login %s password %s\n' \
  "${MP_URL#https://}" \
  "$MP_USER" "$MP_PASSWORD" > "$NETRC"
chmod 600 "$NETRC"

# Helper function to make API calls
mp_api() {
  local method=$1
  local endpoint=$2
  local data=${3:-}

  local curl_opts=("-k" "-sS" "-H" "Content-Type: application/json" "-X" "$method")

  if [ -z "$data" ]; then
    curl "${curl_opts[@]}" --netrc-file "$NETRC" "$MP_URL$endpoint"
  else
    curl "${curl_opts[@]}" --netrc-file "$NETRC" -d "$data" "$MP_URL$endpoint"
  fi
}

# Get health diagnostic status
status=$(mp_api GET /api/health-diagnostic/status)

# Extract categories (all keys except 'total' and 'totalFailed')
categories=$(echo "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

# For each category, get the report and list flagged hosts
for category in $categories; do
  report=$(mp_api POST "/api/health-diagnostic/report/$category" '{"limit": 10000}')

  # Extract hostkeys from rows - first element of each row is the key
  echo "$report" | jq -r --arg cat "$category" '.data[0].rows[]? | $cat + "," + .[0]'
done
```

## Output from hub

```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
```

The script uses the Mission Portal Health Diagnostics API to query all health categories, retrieves the flagged hosts for each category, and outputs them in the requested format with no extra output on stdout.