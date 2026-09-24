The script queries the hub's Health Diagnostic API (`/api/health-diagnostic/status` to discover categories, then `POST /api/health-diagnostic/report/<category>` for each) and extracts the hostkey from each flagged row.

Output from running it against the hub:

```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
```

This matches the hub's own summary count (`totalFailed: 4`).

```bash
#!/usr/bin/env bash
#
# Lists the hosts that CFEngine Mission Portal's Health page currently flags
# as unhealthy.
#
# Prints one line per flagged host to stdout:
#   <category>,<hostkey>
#
# Requires MP_URL, MP_USER, MP_PASSWORD in the environment, and curl + jq
# installed. The hub certificate is expected to be self-signed (curl -k).

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

API="${MP_URL%/}/api/health-diagnostic"
CURL=(curl -sk -u "${MP_USER}:${MP_PASSWORD}")

# Discover the current set of health-diagnostic categories from the status
# endpoint rather than hard-coding them, so newly added categories are picked
# up automatically. "total" / "totalFailed" are summary fields, not categories.
categories=$("${CURL[@]}" "${API}/status" |
    jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

while IFS= read -r category; do
    [ -n "$category" ] || continue

    "${CURL[@]}" -X POST -H 'Content-Type: application/json' -d '{}' \
        "${API}/report/${category}" |
        jq -r --arg category "$category" \
            '.data[0].rows[]? | [$category, .[0]] | @csv' |
        tr -d '"'
done <<<"$categories"
```