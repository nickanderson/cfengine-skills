#!/usr/bin/env bash
# List leftover Mission Portal host records from reinstalled machines.
# A physical/virtual machine is identified by its DMI system UUID
# (dmi[system-uuid]); hostnames alone are not unique (e.g. two distinct
# machines may both call themselves hub.example.com). For every UUID seen
# under more than one hostkey, the record with the latest last report is the
# current identity and every other record is stale.
# Output: <stale hostkey>,<current hostkey>,<hostname>,<ip>   (read-only)
set -euo pipefail
: "${MP_URL:?}" "${MP_USER:?}" "${MP_PASSWORD:?}"

read -r -d '' SQL <<'SQL' || true
WITH ident AS (
  SELECT h.hostkey, h.hostname, h.ipaddress,
         h.lastreporttimestamp, h.firstreporttimestamp,
         upper(trim(v.variablevalue)) AS uuid
  FROM hosts h
  JOIN variables v ON v.hostkey = h.hostkey
  WHERE v.variablename = 'dmi[system-uuid]'
    AND coalesce(trim(v.variablevalue), '') NOT IN ('', '0')
), ranked AS (
  SELECT *, row_number() OVER (PARTITION BY uuid
            ORDER BY lastreporttimestamp DESC NULLS LAST,
                     firstreporttimestamp DESC NULLS LAST, hostkey) AS rn
  FROM ident
)
SELECT s.hostkey, c.hostkey, c.hostname, c.ipaddress
FROM ranked s JOIN ranked c ON c.uuid = s.uuid AND c.rn = 1
WHERE s.rn > 1
ORDER BY c.hostname, s.hostkey
SQL

jq -n --arg q "$SQL" '{query: $q}' |
  curl -sSfk -u "$MP_USER:$MP_PASSWORD" -X POST \
       -H 'Content-Type: application/json' -d @- "$MP_URL/api/query" |
  jq -r '.data[0].rows[] | map(. // "") | join(",")'
