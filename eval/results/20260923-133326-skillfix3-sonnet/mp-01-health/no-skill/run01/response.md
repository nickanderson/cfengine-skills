The script queries the hub's health-diagnostic API directly (not scraping the UI): `GET /api/health-diagnostic/status` to discover the current set of health-check categories, then `POST /api/health-diagnostic/report/<category>` for each one to pull the flagged hosts, extracting the `key` (hostkey) column from each row.

Ran against the hub, current output:

```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
hostsUsingSameName,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4
notRecentlyCollected,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4
```

```bash
#!/usr/bin/env bash
#
# Ask the CFEngine Enterprise hub's Mission Portal which hosts its Health
# page currently flags as unhealthy, and print one line per flagged host:
#
#     <category>,<hostkey>
#
# Requires: MP_URL, MP_USER, MP_PASSWORD in the environment. The hub's TLS
# certificate is expected to be self-signed, so curl is run with -k.

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

curl_api() {
    curl -sk -u "${MP_USER}:${MP_PASSWORD}" "$@"
}

# The set of health-diagnostic report categories is discovered from the
# status endpoint: every key except the two aggregate counters ("total"
# and "totalFailed") names a report that can be fetched individually.
categories=$(curl_api "${MP_URL}/api/health-diagnostic/status" \
    | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

while IFS= read -r category; do
    [ -n "$category" ] || continue

    curl_api -X POST -H "Content-Type: application/json" -d '{}' \
        "${MP_URL}/api/health-diagnostic/report/${category}" \
    | jq -r --arg category "$category" '
        .data[]
        | . as $report
        | ($report.header | map(.columnName) | index("key")) as $i
        | $report.rows[]
        | select($i != null)
        | "\($category),\(.[$i])"
    '
done <<< "$categories"
```