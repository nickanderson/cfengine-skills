#!/usr/bin/env bash
# Find leftover Mission Portal host records left behind by machines that
# were reinstalled and now report under a new CFEngine identity (host key).
#
# For every hostname that Mission Portal has more than one record for, split
# the records into:
#   - "stale": records the hub's own health diagnostics consider not
#     recently collected (i.e. stopped reporting)
#   - "current": records that are still reporting
# When a hostname has both, each stale record is a leftover from before a
# reinstall, and the (single, most recently reporting) current record is
# the identity the machine reports under now. Hostnames where every record
# is still actively reporting are a genuine duplicate-hostname situation,
# not a reinstall, and are skipped.
#
# Output: one CSV line per leftover record, nothing else on stdout.
#   <stale hostkey>,<current hostkey>,<hostname>,<ip>
#
# Configuration (environment):
#   MP_URL       https://hub.example.com   (required)
#   MP_USER      Mission Portal login      (required)
#   MP_PASSWORD  Mission Portal password   (required)
#   MP_CACERT    path to the hub's certificate, for a self-signed hub
#                (if unset, certificate verification is skipped)

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

TLS_ARGS=(-k)
if [ -n "${MP_CACERT:-}" ]; then
  TLS_ARGS=(--cacert "$MP_CACERT")
fi

api() {  # api <method> <path> [json body] -> response body on stdout
  local method=$1 path=$2 data=${3-}
  local -a curlargs=(-sS -X "$method" "${TLS_ARGS[@]}"
                      --connect-timeout 10 --max-time 300
                      "${MP_URL%/}$path")
  if [ -n "$data" ]; then
    curlargs+=(-H "Content-Type: application/json" --data-binary "$data")
  fi
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" | curl -K - "${curlargs[@]}"
}

dup_json=$(api POST /api/health-diagnostic/report/hostsUsingSameName '{"limit":10000}')
stale_json=$(api POST /api/health-diagnostic/report/notRecentlyCollected '{"limit":10000}')

jq -rn \
  --argjson dup "$dup_json" \
  --argjson stale "$stale_json" \
  '
  ($stale.data[0].rows // []) | map(.[0]) as $stalekeys
  | ($dup.data[0].rows // []) as $rows
  | ($rows | group_by(.[2]))[]
  | . as $g
  | ($g | map(select(.[1] as $hk | ($stalekeys | index($hk)) != null))) as $staleset
  | ($g | map(select(.[1] as $hk | ($stalekeys | index($hk)) == null))) as $curset
  | select(($staleset | length) > 0 and ($curset | length) > 0)
  | ($curset | sort_by(.[4]) | last) as $cur
  | $staleset[]
  | "\(.[1]),\($cur[1]),\(.[2]),\($cur[3])"
  '
