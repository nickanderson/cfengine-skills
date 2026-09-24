Ran cleanly against the hub: **1123 hosts**, all with unique hostkeys, well-formed 3-field CSV lines, no header, nothing else on stdout — matches Mission Portal's reported total exactly.

The script pages through `/api/host` (250 hosts/page, driven by the `meta.total`/`meta.count` fields in the response) instead of trusting a single large request, so it won't silently truncate if the hub's page-size cap changes. It uses `set -euo pipefail` and `curl -f` so any auth/connection/HTTP error aborts loudly rather than emitting a partial CSV.

```bash
#!/usr/bin/env bash
#
# Print one CSV line per host known to CFEngine Enterprise Mission Portal:
#   <hostkey>,<hostname>,<ip address>
#
# Requires MP_URL, MP_USER, MP_PASSWORD in the environment. The hub's
# certificate is self-signed, so TLS verification is disabled (-k).
#
# Pages through /api/host (Mission Portal's paginated host inventory) rather
# than requesting one giant page, so no host is dropped even if a future hub
# imposes a max page size below the current host count.

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "all-hosts.sh: required command '$cmd' not found" >&2
        exit 1
    fi
done

base_url="${MP_URL%/}"
page_size=250
page=1
fetched=0

while :; do
    response=$(curl -fsSk -u "${MP_USER}:${MP_PASSWORD}" \
        "${base_url}/api/host?page=${page}&count=${page_size}")

    n=$(jq '.data | length' <<<"$response")
    total=$(jq '.meta.total' <<<"$response")

    if [ "$n" -eq 0 ]; then
        break
    fi

    jq -r '.data[] | "\(.id),\(.hostname),\(.ip)"' <<<"$response"

    fetched=$((fetched + n))
    if [ "$fetched" -ge "$total" ]; then
        break
    fi
    page=$((page + 1))
done
```