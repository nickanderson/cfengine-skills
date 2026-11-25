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
