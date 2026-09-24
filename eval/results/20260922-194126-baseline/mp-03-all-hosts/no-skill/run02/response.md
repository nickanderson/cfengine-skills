## Result

I ran it against the hub and it printed **1122 hosts** (matching the API's own `meta.total: 1122`, and all 1122 hostkeys are unique — no duplicates or missing rows).

How it works: the Mission Portal's REST API exposes hosts at `GET /api/host` (singular — `/api/hosts` 404s), returning paginated JSON with `data` (host records) and `meta.total`. The script pages through with `count=500&page=N` until a page comes back empty, extracting `id` (hostkey), `hostname`, and `ip` into plain CSV lines via `jq`. Paging (rather than requesting everything in one shot) guards against a hub-side cap on very large deployments.

```bash
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
```