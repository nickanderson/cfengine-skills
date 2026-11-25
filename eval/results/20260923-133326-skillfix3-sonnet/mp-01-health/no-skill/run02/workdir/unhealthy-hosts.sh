#!/usr/bin/env bash
# Print "<category>,<hostkey>" for every host currently flagged as unhealthy
# on the CFEngine Mission Portal Health page, using the hub's
# health-diagnostic REST API.
#
# Requires MP_URL, MP_USER, MP_PASSWORD in the environment. The hub's
# certificate is expected to be self-signed (curl is run with -k).

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

API="${MP_URL%/}/api/health-diagnostic"
AUTH=(-u "${MP_USER}:${MP_PASSWORD}")
CURL=(curl -sk --fail "${AUTH[@]}")

# Discover the set of health-diagnostic categories from the summary
# endpoint (it also includes categories missing from /report_ids, e.g.
# hostsUsingSameName), rather than hardcoding them.
status_json=$("${CURL[@]}" "${API}/status")

categories=$(jq -r 'del(.total, .totalFailed) | keys[]' <<<"$status_json")

while IFS= read -r category; do
    [ -z "$category" ] && continue

    report_json=$("${CURL[@]}" -X POST -H "Content-Type: application/json" \
        -d '{"limit": 100000}' "${API}/report/${category}")

    jq -r --arg cat "$category" '
        .data[0] as $d
        | ($d.header | map(.columnName) | index("key")) as $i
        | $d.rows[]?
        | "\($cat),\(.[$i])"
    ' <<<"$report_json"
done <<<"$categories"
