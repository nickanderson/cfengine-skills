#!/usr/bin/env bash
# List Mission Portal host records left behind by reinstalled machines.
#
# A reinstall gives a machine a new CFEngine host key, but its hardware
# identity (SMBIOS system UUID, reported as dmi[system-uuid]) stays the same.
# Records sharing a system UUID are grouped; the record that reported most
# recently is the current one, and every other record in the group that
# stopped reporting before the current one first appeared is stale.
# (The overlap check avoids flagging cloned VMs that share a UUID but are
# both alive.) Hostname is deliberately NOT used as the key: distinct machines
# can report the same hostname.
#
# Output: <stale hostkey>,<current hostkey>,<hostname>,<ip>
# (hostname/ip are those the machine reports under its current record)
# Read-only: nothing is deleted.
#
# Requires: curl, jq. Env: MP_URL, MP_USER, MP_PASSWORD.
set -euo pipefail

: "${MP_URL:?MP_URL not set}" "${MP_USER:?MP_USER not set}" "${MP_PASSWORD:?MP_PASSWORD not set}"

SQL="SELECT h.hostkey, h.hostname, h.ipaddress,
       extract(epoch FROM h.firstreporttimestamp)::bigint AS firstseen,
       extract(epoch FROM h.lastreporttimestamp)::bigint AS lastseen,
       upper(trim(v.variablevalue)) AS uuid
FROM hosts h
JOIN variables v ON v.hostkey = h.hostkey
WHERE v.variablename = 'dmi[system-uuid]'"

payload=$(jq -n --arg q "$SQL" '{query: $q, limit: 1000000}')

resp=$(curl -sS -k --fail -u "$MP_USER:$MP_PASSWORD" \
  -H 'Content-Type: application/json' \
  -X POST "${MP_URL%/}/api/query" -d "$payload") || {
  echo "error: query to $MP_URL failed" >&2; exit 1; }

jq -r '
  .data[0].rows
  | map({key: .[0], hostname: .[1], ip: .[2],
         first: (.[3] | tonumber? // 0), last: (.[4] | tonumber? // 0),
         uuid: .[5]})
  # ignore missing/placeholder UUIDs that do not identify hardware
  | map(select(.uuid != null and .uuid != ""
                and (.uuid | test("^[0F-]+$") | not)))
  | group_by(.uuid)[]
  | select(length > 1)
  | sort_by(.last, .first)
  | last as $cur
  | .[:-1][]
  | select(.last <= $cur.first)
  | [.key, $cur.key, $cur.hostname, $cur.ip] | join(",")
' <<<"$resp"
