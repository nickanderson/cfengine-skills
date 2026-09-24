Clean stdout, no stderr noise, exit 0, and the row count matches the hub's own `totalFailed` count of 4.

I found the CFEngine Enterprise "Health diagnostic API" (`/api/health-diagnostic/status`, `/report_ids`, `/report/:report_id`) — the same API the Mission Portal Health page uses. Notably, `status` exposes a category (`hostsUsingSameName`) that `/report_ids` doesn't list, so the script derives categories from `status` directly to avoid missing any.

**Output from the hub:**
```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
```

**unhealthy-hosts.sh:**
```bash
#!/usr/bin/env bash
#
# Query a CFEngine Enterprise hub's Mission Portal for the hosts currently
# flagged as unhealthy on the Health page, and print one line per flagged
# host as:
#
#   <category>,<hostkey>
#
# Requires MP_URL, MP_USER, MP_PASSWORD in the environment.

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

BASE_URL="${MP_URL%/}/api/health-diagnostic"

curl_api() {
    curl -sS -k -u "${MP_USER}:${MP_PASSWORD}" "$@"
}

# The health-diagnostic/status endpoint reports a count for every category
# the Health page can flag (this includes categories such as
# "hostsUsingSameName" that are not listed by /report_ids), plus the two
# summary fields "totalFailed" and "total". Derive the category list from
# it so we don't miss any flagged category.
status_json="$(curl_api "${BASE_URL}/status")"

categories="$(printf '%s' "$status_json" | jq -r 'keys[] | select(. != "totalFailed" and . != "total")')"

while IFS= read -r category; do
    [ -n "$category" ] || continue
    report_json="$(curl_api -X POST -H "Content-Type: application/json" -d '{}' \
        "${BASE_URL}/report/${category}")"

    printf '%s\n' "$report_json" | jq -r --arg category "$category" \
        '.data[0].rows[]? | [$category, .[0]] | @csv' \
        | sed 's/"//g'
done <<< "$categories"
```