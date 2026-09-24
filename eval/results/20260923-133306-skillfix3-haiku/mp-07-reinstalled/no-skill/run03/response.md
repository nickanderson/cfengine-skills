Perfect! The script is working correctly. It found one stale record. Here's the final script:

```bash
#!/bin/bash

set -u

MP_URL="${MP_URL}"
MP_USER="${MP_USER}"
MP_PASSWORD="${MP_PASSWORD}"

if [ -z "$MP_URL" ] || [ -z "$MP_USER" ] || [ -z "$MP_PASSWORD" ]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD environment variables must be set" >&2
    exit 1
fi

# Fetch hosts and identify stale records
# Group by hostname+ip, sort by lastreport, output stale ones (non-current)
curl -s -k -u "${MP_USER}:${MP_PASSWORD}" \
    "${MP_URL}/api/host" | \
jq -r '
    .data |
    group_by(.hostname + "|" + .ip) |
    .[] |
    select(length > 1) |
    sort_by(.lastreport | tonumber) | reverse |
    .[0] as $current |
    .[1:] |
    .[] |
    "\(.id),\($current.id),\(.hostname),\(.ip)"
'
```

**Output from running against the hub:**

```
SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5,host004.example.com,192.168.56.6
```

This shows one leftover record for `host004.example.com`: the old host key (`SHA=714a84...`) has been superseded by a new one (`SHA=06791f...`), likely from a reinstallation on that machine.