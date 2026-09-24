#!/usr/bin/env bash
#
# Find Mission Portal host records left behind by reinstalled machines.
#
# A reinstalled machine keeps its hostname but starts reporting under a new
# CFEngine identity (host key). Mission Portal then holds two (or more)
# records for the same hostname: an old one that stopped reporting, and the
# current one the machine reports under now. This prints one line per
# leftover ("stale") record:
#
#   <stale hostkey>,<current hostkey>,<hostname>,<ip>
#
# A hostname shared by several *currently reporting* hosts (e.g. a host with
# two NICs reporting separately) is a genuine duplicate, not a leftover, and
# is not printed.
#
# Needs: MP_URL, MP_USER, MP_PASSWORD; MP_CACERT (the hub's certificate) optional.
set -euo pipefail

: "${MP_URL:?MP_URL is required}"
: "${MP_USER:?MP_USER is required}"
: "${MP_PASSWORD:?MP_PASSWORD is required}"

tls=(-k)
[ -n "${MP_CACERT:-}" ] && tls=(--cacert "$MP_CACERT")

mp() {  # mp <METHOD> <path> [json-body] -> response body; fails on HTTP errors
  local method="$1" path="$2"
  local -a body=()
  [ $# -ge 3 ] && body=(-H 'Content-Type: application/json' --data-binary "$3")
  curl -sS --fail-with-body "${tls[@]}" \
    --netrc-file <(printf 'default login %s password %s\n' "$MP_USER" "$MP_PASSWORD") \
    -X "$method" "${body[@]}" "$MP_URL$path"
}

# Mission Portal's own "Unreachable hosts" threshold (seconds); a host whose
# last report is older than this counts as no longer reporting. Falls back to
# the documented default if settings can't be read for any reason.
horizon=$(mp GET /api/settings | jq -r '.data[0].blueHostHorizon // empty' 2>/dev/null || true)
case "$horizon" in
  ''|*[!0-9]*) horizon=900 ;;
esac

query=$(cat <<SQL
WITH dup AS (
  SELECT hostkey, hostname, ipaddress, lastreporttimestamp,
         (now() - lastreporttimestamp) > interval '$horizon seconds' AS is_stale
  FROM hosts
  WHERE hostname IN (SELECT hostname FROM hosts GROUP BY hostname HAVING COUNT(*) > 1)
)
SELECT s.hostkey, c.hostkey, s.hostname, c.ipaddress
FROM dup s
JOIN dup c ON c.hostname = s.hostname AND s.is_stale = true AND c.is_stale = false
SQL
)

payload=$(jq -n --arg q "$query" '{query: $q}')
mp POST /api/query "$payload" | jq -r '.data[0].rows[]? | @tsv' | tr '\t' ','
