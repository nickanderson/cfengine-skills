#!/usr/bin/env bash
#
# Print one CSV line per host known to CFEngine Mission Portal:
#   <hostkey>,<hostname>,<ip address>
#
# Requires MP_URL, MP_USER, MP_PASSWORD in the environment.
# Uses curl -k because the hub's certificate is self-signed.

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

page_count=500
page=1

while :; do
    response=$(curl -sS -k -u "${MP_USER}:${MP_PASSWORD}" \
        "${MP_URL}/api/host?count=${page_count}&page=${page}")

    status=0
    fetched=$(printf '%s\n' "$response" | python3 -c '
import json, sys
d = json.load(sys.stdin)
rows = d.get("data", [])
for h in rows:
    print("%s,%s,%s" % (h["id"], h["hostname"], h["ip"]))
sys.exit(0 if len(rows) == '"$page_count"' else 1)
') || status=$?

    if [ -n "$fetched" ]; then
        printf '%s\n' "$fetched"
    fi

    if [ "$status" -ne 0 ]; then
        break
    fi
    page=$((page + 1))
done
