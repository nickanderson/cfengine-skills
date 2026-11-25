Perfect! The script successfully identified the stale records. Here's the final script and its output:

## Script: stale-records.sh

```bash
#!/bin/bash

# Find stale CFEngine host records in Mission Portal
# Stale records are leftover from machines that were reinstalled with new host keys

set -o pipefail

# Validate required environment variables
if [[ -z "$MP_URL" || -z "$MP_USER" || -z "$MP_PASSWORD" ]]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD environment variables must be set" >&2
    exit 1
fi

# Query Mission Portal API for all hosts
# -k: ignore SSL certificate verification (self-signed cert)
# -u: basic authentication
# -f: fail on HTTP errors
RESPONSE=$(curl -s -k -f -u "$MP_USER:$MP_PASSWORD" "$MP_URL/api/host" 2>&1)

EXIT_CODE=$?
if [[ $EXIT_CODE -ne 0 ]]; then
    echo "Error: Failed to query Mission Portal at $MP_URL (exit code: $EXIT_CODE)" >&2
    echo "$RESPONSE" >&2
    exit 1
fi

# Validate JSON response
if ! echo "$RESPONSE" | jq empty 2>/dev/null; then
    echo "Error: Mission Portal returned invalid JSON" >&2
    exit 1
fi

# Find stale records:
# 1. Group hosts by hostname
# 2. For each hostname with multiple keys:
#    - Sort by lastreport (most recent first)
#    - Mark the most recent as "current"
#    - Print all others as stale with format: <stale key>,<current key>,<hostname>,<ip>

jq -r '
  .data |
  group_by(.hostname) |
  .[] |
  if length > 1 then
    sort_by(.lastreport | tonumber) |
    reverse |
    .[0] as $current |
    .[] |
    select(.id != $current.id) |
    "\(.id),\($current.id),\(.hostname),\(.ip)"
  else
    empty
  end
' <<< "$RESPONSE"

exit 0
```

## Output from the hub:

```
SHA=c80bed38648aaeb68773826a6fb9a874baab9373db69b95099ef065541de1869,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,host004.example.com,192.168.56.6
SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940,hub.example.com,192.168.56.5
```

**Summary:** The script found 2 stale records:
- **host004.example.com** was reinstalled and obtained a new host key (`SHA=714a84...`); the old key (`SHA=c80bed...`) is stale
- **hub.example.com** was reinstalled and obtained a new host key (`SHA=6bb77...`); the old key (`SHA=f20cf...`) is stale

The script uses `lastreport` timestamps to determine which key is current (most recently active) and marks all others for that hostname as stale.