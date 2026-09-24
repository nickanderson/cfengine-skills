Clean output, nothing on stderr, and it confirms 4 hosts flagged unhealthy on this hub right now.

I discovered the endpoint by tracing Mission Portal's own Health page (Reports → Health diagnostic) through its Angular front-end: it calls `POST /api/health-diagnostic/report/<type>` with basic auth for each of 7 fixed sub-reports, returning a `rows` array whose first column is the host's `SHA=...` key.

**Output from the hub:**
```
duplicate-hostnames,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
duplicate-hostnames,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
outdated-reporting-data,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deleted-hosts-report,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
```

```bash
#!/usr/bin/env bash
#
# Ask the CFEngine Enterprise hub's Mission Portal which hosts its Health
# page currently flags as unhealthy, and print one line per flagged host:
#
#   <category>,<hostkey>
#
# Requires MP_URL, MP_USER, MP_PASSWORD in the environment (self-signed
# certificate is tolerated). Depends on curl and jq.
#
# The Mission Portal "Health" page (Reports > Health diagnostic) is made up
# of a fixed set of sub-reports, each backed by the hub's
# /api/health-diagnostic/report/<type> endpoint. <category> below uses the
# same slug Mission Portal uses in its own report URLs
# (/reports/health-diagnostic/<category>).

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

# internal report type -> Mission Portal category slug
declare -A REPORTS=(
    [notRecentlyCollected]=unreachable-hosts
    [lastAgentRunUnsuccessful]=policy-errors
    [hostsUsingSameIdentity]=duplicate-ids
    [hostsNeverCollected]=missing-reporting-data
    [deletedHostsReport]=deleted-hosts-report
    [agentNotRunRecently]=outdated-reporting-data
    [hostsUsingSameName]=duplicate-hostnames
)

for report_type in "${!REPORTS[@]}"; do
    category=${REPORTS[$report_type]}

    response=$(curl -sk -u "${MP_USER}:${MP_PASSWORD}" \
        -X POST \
        -H 'Content-Type: application/json' \
        -d '{"sortColumn":"","sortDescending":0,"skip":0,"limit":-1}' \
        "${MP_URL%/}/api/health-diagnostic/report/${report_type}")

    echo "$response" | jq -e '.data[0].rows' >/dev/null 2>&1 || {
        echo "unhealthy-hosts.sh: failed to fetch report '${report_type}': $response" >&2
        continue
    }

    echo "$response" | jq -r --arg category "$category" \
        '.data[0].rows[][0] | "\($category),\(.)"'
done
```