#!/usr/bin/env bash
#
# Print one CSV line per host known to CFEngine Enterprise Mission Portal:
#   <hostkey>,<hostname>,<ip address>
#
# Reads connection details from the environment:
#   MP_URL      - base URL of the hub, e.g. https://192.168.56.2
#   MP_USER     - Mission Portal username
#   MP_PASSWORD - Mission Portal password
#
# The hub's certificate is self-signed, so TLS verification is disabled (-k).

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

PAGE_SIZE=500
page=1

while :; do
    response=$(curl -sk --fail-with-body \
        -u "${MP_USER}:${MP_PASSWORD}" \
        "${MP_URL}/api/host?count=${PAGE_SIZE}&page=${page}")

    n=$(printf '%s' "$response" | jq '.data | length')
    if [ "$n" -eq 0 ]; then
        break
    fi

    printf '%s' "$response" | jq -r '.data[] | "\(.id),\(.hostname),\(.ip)"'

    page=$((page + 1))
done
