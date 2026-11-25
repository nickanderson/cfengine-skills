#!/usr/bin/env bash
#
# Ask a CFEngine Enterprise hub's Mission Portal which hosts the Health page
# currently flags as unhealthy, and print one "<category>,<hostkey>" line
# per flagged host.
#
# Requires: MP_URL, MP_USER, MP_PASSWORD (self-signed cert is tolerated via -k)
#
# Uses the Health diagnostic API:
#   POST /api/health-diagnostic/report/:report_id
# https://docs.cfengine.com/docs/lts/api/enterprise-api-ref/health-diagnostic/

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

# These are exactly the report categories the Mission Portal Health page checks.
CATEGORIES=(
  hostsNeverCollected
  deletedHostsReport
  notRecentlyCollected
  hostsUsingSameIdentity
  agentNotRunRecently
  lastAgentRunUnsuccessful
)

for category in "${CATEGORIES[@]}"; do
  response=$(curl -sk \
    -u "${MP_USER}:${MP_PASSWORD}" \
    -X POST "${MP_URL%/}/api/health-diagnostic/report/${category}" \
    -H 'Content-Type: application/json' \
    -d '{"limit": 1000}')

  echo "$response" | jq -r --arg category "$category" '
    .data[0] as $report
    | ($report.header | map(.columnName) | index("hostkey")) as $hostkeyIdx
    | ($report.header | map(.columnName) | index("key")) as $keyIdx
    | ($hostkeyIdx // $keyIdx) as $idx
    | $report.rows[]
    | "\($category),\(.[$idx])"
  '
done
