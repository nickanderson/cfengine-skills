No stderr output, clean exit. The script is ready.

## Summary

`all-hosts.sh` queries the Mission Portal's REST API (`/api/host`, discovered by probing — it's `host`, not `hosts`), which paginates at 50 records/page. It loops through pages using `jq` to parse each response, stopping once the cumulative count reaches `meta.total`, and emits `<hostkey>,<hostname>,<ip>` per host with no header or extra output.

**Ran against the hub: it printed 1122 hosts**, all with unique hostkeys and well-formed 3-field CSV rows, no missing fields or embedded commas found in the source data.

```bash
#!/usr/bin/env bash
#
# Print one CSV line per host known to CFEngine Enterprise Mission Portal:
#   <hostkey>,<hostname>,<ip address>
#
# Reads connection details from the environment:
#   MP_URL      - base URL of the hub's Mission Portal (e.g. https://hub.example.com)
#   MP_USER     - API username
#   MP_PASSWORD - API password
#
# The hub's certificate is self-signed, so TLS verification is disabled (-k).

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

page=1
total=""
count_seen=0

while :; do
  response=$(curl -sk -f -u "${MP_USER}:${MP_PASSWORD}" \
    "${MP_URL%/}/api/host?page=${page}")

  # Stop once the hub reports no more rows.
  page_count=$(jq -r '.data | length' <<<"$response")
  if [ "$page_count" -eq 0 ]; then
    break
  fi

  jq -r '.data[] | "\(.id),\(.hostname),\(.ip)"' <<<"$response"

  count_seen=$((count_seen + page_count))

  if [ -z "$total" ]; then
    total=$(jq -r '.meta.total' <<<"$response")
  fi

  if [ -n "$total" ] && [ "$total" != "null" ] && [ "$count_seen" -ge "$total" ]; then
    break
  fi

  page=$((page + 1))
done
```