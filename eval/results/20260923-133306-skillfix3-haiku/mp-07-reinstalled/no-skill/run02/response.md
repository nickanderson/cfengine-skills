Excellent! The script successfully found 2 stale host records in your Mission Portal:

**Script output:**
```
SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5,host004.example.com,192.168.56.6
SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940,hub.example.com,192.168.56.5
```

The script identified:
1. **host004.example.com** - has one stale hostkey that was replaced with a new one
2. **hub.example.com** - has one stale hostkey that was replaced with a new one

**Final script (`stale-records.sh`):**
```bash
#!/bin/bash

set -euo pipefail

MP_URL="${MP_URL?Mission Portal URL not set}"
MP_USER="${MP_USER?Mission Portal user not set}"
MP_PASSWORD="${MP_PASSWORD?Mission Portal password not set}"

# Fetch all hosts from Mission Portal API
RESPONSE=$(curl -s -k -u "$MP_USER:$MP_PASSWORD" "$MP_URL/api/host")

# Process the JSON to find stale records
# Group by hostname, find those with multiple hostkeys, output stale ones
echo "$RESPONSE" | jq -r '
.data |
group_by(.hostname) |
.[] |
select(length > 1) |
. as $group |
(
  # Determine current hostkey (most recently reported/seen)
  ($group | max_by(.lastreport | tonumber) | .id) as $current
  |
  # Output each stale record
  $group[] |
  select(.id != $current) |
  [.id, $current, .hostname, .ip] |
  join(",")
)
'
```

The script queries the Mission Portal API, groups records by hostname, identifies which hostkey is current (most recent lastreport), and outputs stale records in the requested format: `<stale hostkey>,<current hostkey>,<hostname>,<ip>`.