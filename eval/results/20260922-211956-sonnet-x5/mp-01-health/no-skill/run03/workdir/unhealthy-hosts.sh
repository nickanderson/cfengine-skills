#!/usr/bin/env bash
#
# List hosts currently flagged as unhealthy on the CFEngine Mission Portal
# Health page, one "<category>,<hostkey>" line per flagged host.
#
# Requires: MP_URL, MP_USER, MP_PASSWORD in the environment. curl, jq.

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

curl_json() {
    # $1 = HTTP method, $2 = path (after /api), rest = extra curl args
    local method="$1" path="$2"
    shift 2
    curl -sk -u "${MP_USER}:${MP_PASSWORD}" -X "${method}" \
        "${MP_URL%/}/api${path}" "$@"
}

# The set of health-diagnostic categories is whatever the hub's status
# endpoint reports (excluding the aggregate "total"/"totalFailed" fields).
# This is more robust than the report_ids endpoint, which is known to omit
# at least one valid category (hostsUsingSameName).
status_json=$(curl_json GET /health-diagnostic/status)

categories=$(jq -r 'keys[] | select(. != "total" and . != "totalFailed")' <<<"${status_json}")

while IFS= read -r category; do
    [ -z "${category}" ] && continue

    count=$(jq -r --arg c "${category}" '.[$c]' <<<"${status_json}")
    # Status may report "n/a" for categories the user lacks permission to view.
    [ "${count}" = "0" ] && continue
    [ "${count}" = "n/a" ] && continue

    report_json=$(curl_json POST "/health-diagnostic/report/${category}" \
        -H 'Content-Type: application/json' -d '{}')

    jq -r --arg cat "${category}" \
        '.data[0].rows[] | [$cat, .[0]] | @csv' <<<"${report_json}" \
        | tr -d '"'
done <<<"${categories}"
