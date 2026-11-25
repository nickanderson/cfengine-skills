Perfect! The script successfully queries the hub and returns the unhealthy hosts. Here's the final script:

```bash
#!/bin/bash

set -euo pipefail

# Get status to find which categories have flagged hosts
status=$(curl -sS -k -u "$MP_USER:$MP_PASSWORD" "$MP_URL/api/health-diagnostic/status")

# Extract all category keys (skip 'total' and 'totalFailed')
categories=$(echo "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

# For each category, fetch the report and output hosts
for category in $categories; do
  response=$(curl -sS -k -u "$MP_USER:$MP_PASSWORD" "$MP_URL/api/health-diagnostic/report/$category" \
    -H "Content-Type: application/json" \
    -d '{"limit": 10000}')
  
  # Extract hostkeys from rows and output as category,hostkey
  echo "$response" | jq -r '.data[0].rows[]? | "'"$category"',\(.[0])"' 2>/dev/null || true
done
```

**Output from the hub:**

```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
```

The hub has 4 flagged hosts: one with outdated reporting data, one deleted host still reporting, and two hosts sharing the same hostname.