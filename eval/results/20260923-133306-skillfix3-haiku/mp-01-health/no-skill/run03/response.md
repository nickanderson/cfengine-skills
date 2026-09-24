Done! Here's the complete script:

```bash
#!/bin/bash

set -e

MP_URL="${MP_URL:-https://192.168.56.2}"
MP_USER="${MP_USER:-admin}"
MP_PASSWORD="${MP_PASSWORD:-<redacted>}"

# Get health report IDs (categories)
report_ids=$(curl -s -k -u "${MP_USER}:${MP_PASSWORD}" \
  "${MP_URL}/api/health-diagnostic/report_ids" | jq -r '.[]')

# Also get status keys that might not be in report_ids
status_keys=$(curl -s -k -u "${MP_USER}:${MP_PASSWORD}" \
  "${MP_URL}/api/health-diagnostic/status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

# Combine and deduplicate report IDs
all_ids=$(printf "%s\n" "$report_ids" "$status_keys" | sort -u)

# For each report ID, fetch the hosts
for rid in $all_ids; do
  curl -s -k -u "${MP_USER}:${MP_PASSWORD}" \
    "${MP_URL}/api/health-diagnostic/report/${rid}" \
    -H "Content-Type: application/json" \
    -d '{"limit": 10000}' 2>/dev/null | \
    jq -r ".data[0].rows[]? | .[0]" 2>/dev/null | \
    while read -r hostkey; do
      [ -n "$hostkey" ] && echo "$rid,$hostkey"
    done
done
```

**Output against the hub:**

```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
hostsUsingSameName,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4
notRecentlyCollected,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4
```

The script queries the Mission Portal's health-diagnostic REST API endpoints to identify unhealthy hosts and categorizes them accordingly.