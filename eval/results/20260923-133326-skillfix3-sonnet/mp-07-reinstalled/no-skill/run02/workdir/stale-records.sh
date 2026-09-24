#!/usr/bin/env bash
#
# stale-records.sh
#
# Finds leftover Mission Portal host records left behind when a machine was
# reinstalled and came back reporting under a new CFEngine host key.
#
# A machine's network identity (hostname, ip) is assumed stable across a
# reinstall, while its host key changes. So for every (hostname, ip) pair
# that has more than one distinct host key on record, the key with the most
# recent report is the machine's current identity, and every other key in
# that group is a leftover ("stale") record from before the reinstall.
#
# Records that merely share a hostname (or merely share an ip) but not both
# are treated as distinct machines and are not reported.
#
# Output (stdout), one line per leftover record, nothing else:
#   <stale hostkey>,<current hostkey>,<hostname>,<ip>
#
# Requires: curl, jq
# Uses env vars: MP_URL, MP_USER, MP_PASSWORD

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

curl -sk -u "${MP_USER}:${MP_PASSWORD}" \
    "${MP_URL%/}/api/host?limit=10000" \
| jq -r '
    .data
    # group records by their (hostname, ip) network identity
    | group_by([.hostname, .ip])
    | map(select(length > 1))
    | map(
        (max_by(.lastreport | tonumber)) as $current
        | .[]
        | select(.id != $current.id)
        | [.id, $current.id, .hostname, .ip]
        | @csv
      )
    | .[]
  ' \
| tr -d '"'
