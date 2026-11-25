The script ran cleanly, exit code 0, self-checked against the hub's reported total, and produced 1123 lines — all with exactly 3 fields, all hostkeys unique.

**Result: `all-hosts.sh` printed 1123 hosts.**

It works by paging through `GET /api/host` (fixed page size of 50) until an empty page is returned, extracting `id`/`hostname`/`ip` from each entry, and verifying the count printed matches `meta.total` from the hub (exiting non-zero if they disagree, so a partial/failed fetch won't silently under-report to the CMDB).

```bash
#!/usr/bin/env bash
#
# Prints one CSV line per host known to CFEngine Enterprise Mission Portal:
#   <hostkey>,<hostname>,<ip address>
#
# Requires MP_URL, MP_USER, MP_PASSWORD in the environment. The hub's
# certificate is self-signed, so TLS verification is disabled (-k).

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

base_url="${MP_URL%/}"
page=1
total_expected=""
printed=0

while :; do
  response=$(curl -sk --fail -u "${MP_USER}:${MP_PASSWORD}" \
    "${base_url}/api/host?page=${page}")

  if [ -z "$total_expected" ]; then
    total_expected=$(printf '%s' "$response" | jq -r '.meta.total')
  fi

  count=$(printf '%s' "$response" | jq '.data | length')
  if [ "$count" -eq 0 ]; then
    break
  fi

  printf '%s' "$response" | jq -r '.data[] | [.id, .hostname, .ip] | @csv' | tr -d '"'

  printed=$((printed + count))
  page=$((page + 1))
done

if [ -n "$total_expected" ] && [ "$printed" -ne "$total_expected" ]; then
  echo "all-hosts.sh: printed ${printed} hosts but hub reported ${total_expected} total" >&2
  exit 1
fi
```