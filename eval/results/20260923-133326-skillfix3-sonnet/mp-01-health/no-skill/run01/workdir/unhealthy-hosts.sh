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
