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
