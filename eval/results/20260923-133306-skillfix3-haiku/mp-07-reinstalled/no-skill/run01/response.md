Excellent! The script found a stale record. Here's the complete solution:

## stale-records.sh

```bash
#!/bin/bash

set -e

MP_URL="${MP_URL:-https://localhost:8005}"
MP_USER="${MP_USER}"
MP_PASSWORD="${MP_PASSWORD}"

if [[ -z "$MP_USER" || -z "$MP_PASSWORD" ]]; then
    echo "Error: MP_USER and MP_PASSWORD must be set" >&2
    exit 1
fi

CURL_OPTS=("-k" "-s" "-L" "-u" "$MP_USER:$MP_PASSWORD")

# Get all hosts from Mission Portal query API
QUERY_RESULT=$(curl "${CURL_OPTS[@]}" -X POST -H "Content-Type: application/json" \
  -d '{"query":"SELECT hostkey, hostname, ipaddress, lastreporttimestamp FROM hosts"}' \
  "$MP_URL/api/query")

if [[ -z "$QUERY_RESULT" ]]; then
    exit 1
fi

# Process query result to find stale records
# Group by hostname+ipaddress, for each group find the newest (by lastreporttimestamp)
# All others in the group are stale
echo "$QUERY_RESULT" | jq -r '
  .data[0] as $data |
  $data.header | map(.columnName) as $headers |
  ($headers | index("hostkey")) as $hk |
  ($headers | index("hostname")) as $hn |
  ($headers | index("ipaddress")) as $ip |
  ($headers | index("lastreporttimestamp")) as $ts |
  ($data.rows | map({
    hostkey: .[$hk],
    hostname: .[$hn],
    ipaddress: .[$ip],
    timestamp: .[$ts]
  })) |
  group_by([.hostname, .ipaddress]) |
  .[] |
  if length > 1 then
    sort_by(.timestamp) | reverse |
    .[0] as $current |
    .[1:] | .[] |
    "\(.hostkey),\($current.hostkey),\(.hostname),\(.ipaddress)"
  else
    empty
  end
'
```

## Output

```
SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5,host004.example.com,192.168.56.6
```

The script identifies **host004.example.com** (192.168.56.6) as having a stale hostkey. The old hostkey `SHA=714a8...` (last reported at 12:23:37) has been replaced by the new hostkey `SHA=06791...` (last reported at 19:10:14) after the machine was reinstalled.