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
