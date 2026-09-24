#!/usr/bin/env bash
#
# stale-records.sh — find Mission Portal host records left behind by
# machines that were reinstalled (and therefore now report under a new
# CFEngine host key).
#
# For every hostname that has more than one host record, exactly one of
# those records is expected to be the one the machine currently reports
# under (its last report is recent). Any other record for that same
# hostname whose last report is old is a leftover from before the
# reinstall. Hostnames where more than one record is currently reporting
# (or none are) are left alone, since there is no reinstall to infer.
#
# Output: one CSV line per leftover record on stdout, nothing else:
#   <stale hostkey>,<current hostkey>,<hostname>,<ip>

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

# A record counts as "reporting now" if its lastreport is within this many
# seconds of the hub's current time. CFEngine agents report every few
# minutes by default, so this comfortably covers normal jitter while still
# treating anything left over from before a reinstall as stale.
RECENT_WINDOW="${RECENT_WINDOW:-900}"

response=$(curl -sS -k -f -u "${MP_USER}:${MP_PASSWORD}" \
  "${MP_URL%/}/api/host?limit=100000")

echo "$response" | jq -r --argjson window "$RECENT_WINDOW" '
  .meta.timestamp as $now
  | (.data | map(.lastreport |= tonumber | .firstseen |= tonumber)) as $hosts
  | $hosts
  | group_by(.hostname)
  | map(select(length > 1))
  | map(
      . as $group
      | ($group | map(select(($now - .lastreport) <= $window))) as $active
      | if ($active | length) == 1 then
          ($active[0]) as $current
          | $group
          | map(select(.id != $current.id))
          | map("\(.id),\($current.id),\($current.hostname),\($current.ip)")
        else
          []
        end
    )
  | flatten[]
'
