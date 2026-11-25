#!/usr/bin/env bash
# List leftover Mission Portal host records from reinstalled machines.
#
# A reinstalled machine gets a new CFEngine host key but keeps its hardware
# identity (DMI system UUID). Records sharing a system UUID are the same
# machine; the one that reported most recently is its current record, and the
# others are stale.
#
# Output: <stale hostkey>,<current hostkey>,<hostname>,<ip>
# Requires: curl, jq. Env: MP_URL, MP_USER, MP_PASSWORD. Read-only.
set -euo pipefail

: "${MP_URL:?MP_URL not set}" "${MP_USER:?MP_USER not set}" "${MP_PASSWORD:?MP_PASSWORD not set}"

sql="SELECT h.hostkey, h.hostname, h.ipaddress,
            extract(epoch FROM h.lastreporttimestamp)::bigint,
            extract(epoch FROM h.firstreporttimestamp)::bigint,
            upper(trim(v.variablevalue))
     FROM hosts h
     JOIN variables v ON v.hostkey = h.hostkey
     WHERE v.variablename = 'dmi[system-uuid]'"

payload=$(jq -n --arg q "$sql" '{query: $q}')

resp=$(curl -sSk --fail -u "$MP_USER:$MP_PASSWORD" \
  -H 'Content-Type: application/json' -X POST \
  -d "$payload" "$MP_URL/api/query") || { echo "query API request failed" >&2; exit 1; }

jq -r '
  [ .data[0].rows[]
    | {key: .[0], host: (.[1] // ""), ip: (.[2] // ""),
       last: ((.[3] // "0") | tonumber), first: ((.[4] // "0") | tonumber),
       uuid: (.[5] // "")}
    # skip missing / placeholder UUIDs that do not identify hardware
    | select(.uuid != "" and (.uuid | test("^[0F-]+$") | not)
             and .uuid != "03000200-0400-0500-0006-000700080009"
             and (.uuid | test("NOT (SETTABLE|SPECIFIED|PRESENT)") | not))
  ]
  | unique_by(.key)
  | group_by(.uuid)[]
  | select(length > 1)
  | sort_by(.last, .first) | reverse
  | .[0] as $cur
  | .[1:][]
  | [.key, $cur.key, $cur.host, $cur.ip] | join(",")
' <<<"$resp"
