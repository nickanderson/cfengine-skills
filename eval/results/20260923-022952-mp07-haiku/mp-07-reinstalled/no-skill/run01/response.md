Perfect! The script found the stale records. Here's the complete script:

```bash
#!/bin/bash

# Script to find stale host records in CFEngine Enterprise Mission Portal
# Prints: <stale hostkey>,<current hostkey>,<hostname>,<ip>
# 
# Stale records are identified by hostname with multiple hostkeys.
# For each hostname, the current record is determined by:
#   1. Most recent lastreport timestamp (machine still reporting in)
#   2. If tied, use earliest firstseen (the older, original record is current)

MP_URL="${MP_URL:-https://localhost}"
MP_USER="${MP_USER:-admin}"
MP_PASSWORD="${MP_PASSWORD:-}"

curl -s -k -u "${MP_USER}:${MP_PASSWORD}" "${MP_URL}/api/host" 2>/dev/null | jq -r '
    .data | group_by(.hostname) | .[] |
    select(length > 1) |
    . as $hosts |
    # Find current record: sort by lastreport DESC, then firstseen ASC (older firstseen is more current)
    ($hosts | sort_by((-(.lastreport | tonumber)), (.firstseen | tonumber)) | .[0]) as $current |
    # Output all other records as stale
    .[] | select(.id != $current.id) |
    "\(.id),\($current.id),\(.hostname),\(.ip)"
' 2>/dev/null || true
```

**Script output:**
```
SHA=c80bed38648aaeb68773826a6fb9a874baab9373db69b95099ef065541de1869,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,host004.example.com,192.168.56.6
SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940,hub.example.com,192.168.56.5
```

The script identifies 2 leftover records:
1. **host004.example.com** — the machine was reinstalled with a new hostkey (714a84...) but the old record (c80bed38...) remains
2. **hub.example.com** — there's an old hub record at 192.168.56.5 (f20cfa67...) with a stale hostkey; the current hub is at 192.168.56.2 (6bb77202...)