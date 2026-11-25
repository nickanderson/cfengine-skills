Ran `all-hosts.sh` against the hub at `$MP_URL`. Findings and result:

- Mission Portal's REST API on this hub (CFEngine Enterprise 3.27.1) exposes hosts at `/api/host` (singular), not `/api/hosts` — that endpoint returns 404. It's paginated with a fixed page size of 50 (the `limit` parameter is ignored), so the script pages through `?page=1,2,3,...` until a page comes back empty, and cross-checks the running count against `meta.total` from the first page, exiting non-zero if they don't match — so it can't silently under-report to the CMDB.
- Each host record has `id` (the hostkey, e.g. `SHA=...`), `hostname`, and `ip`, which map directly to the required CSV columns.

**Result: it printed exactly 1123 hosts** — matching Mission Portal's reported total, all 1123 hostkeys unique, every line well-formed `hostkey,hostname,ip` with no header or extra output on stdout.

```bash
#!/usr/bin/env bash
# Print one CSV line per host known to CFEngine Enterprise Mission Portal:
#   <hostkey>,<hostname>,<ip address>
# Reads connection info from MP_URL, MP_USER, MP_PASSWORD.
set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

base_url="${MP_URL%/}/api/host"
curl_opts=(-sk -f --connect-timeout 10 -u "${MP_USER}:${MP_PASSWORD}")

page=1
printed=0
expected_total=

while true; do
    response=$(curl "${curl_opts[@]}" "${base_url}?page=${page}") \
        || { echo "all-hosts.sh: request for page ${page} failed" >&2; exit 1; }

    count=$(jq -r '.data | length' <<<"$response")

    if [ "$page" -eq 1 ]; then
        expected_total=$(jq -r '.meta.total' <<<"$response")
    fi

    if [ "$count" -eq 0 ]; then
        break
    fi

    jq -r '.data[] | "\(.id),\(.hostname),\(.ip)"' <<<"$response"

    printed=$((printed + count))
    page=$((page + 1))
done

if [ -n "$expected_total" ] && [ "$printed" -ne "$expected_total" ]; then
    echo "all-hosts.sh: printed ${printed} hosts but Mission Portal reports ${expected_total} total" >&2
    exit 1
fi
```