#!/usr/bin/env bash
# Find leftover Mission Portal host records left behind by reinstalled
# machines: a reinstalled machine keeps its hostname and IP but reports
# under a brand new host key, leaving its old record stuck in the
# inventory. We detect that by grouping all host records by
# (hostname, ip) and, within any group with more than one record,
# treating every record except the most-recently-reporting one as stale.
#
# Output (stdout only): <stale hostkey>,<current hostkey>,<hostname>,<ip>
# One line per leftover record. Nothing is deleted.

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

base_url="${MP_URL%/}"

# Pull every host record in one page (items set high enough to cover
# any realistic inventory; the hub reports a total in .meta so we size
# the request from that instead of hardcoding a magic number).
total=$(curl -sk -u "${MP_USER}:${MP_PASSWORD}" "${base_url}/api/host?items=1" \
  | jq -r '.meta.total')

curl -sk -u "${MP_USER}:${MP_PASSWORD}" "${base_url}/api/host?items=$((total > 0 ? total : 1))" \
| jq -r '
    .data
    | group_by([.hostname, .ip])
    | map(select(length > 1))
    | map(
        (max_by(.lastreport | tonumber)) as $current
        | .[]
        | select(.id != $current.id)
        | [.id, $current.id, .hostname, .ip]
        | join(",")
      )
    | .[]
  '
