#!/usr/bin/env bash
# List Mission Portal host records left behind by reinstalled machines.
#
# A reinstalled machine gets a new host key but keeps its hardware (SMBIOS)
# UUID, inventoried as dmi[system-uuid]. Records sharing a UUID are the same
# machine; the newest identity is the current record, and an older record is
# stale if it stopped reporting before the current one first reported (so
# cloned VMs that share a UUID but both still report are not flagged).
#
# Output: <stale hostkey>,<current hostkey>,<hostname>,<ip>   (read-only)
#
# Env: MP_URL, MP_USER, MP_PASSWORD; optional MP_CACERT (PEM of the hub's
# certificate). Without MP_CACERT, TLS verification is skipped (-k).
set -euo pipefail

: "${MP_URL:?set MP_URL}" "${MP_USER:?set MP_USER}" "${MP_PASSWORD:?set MP_PASSWORD}"
command -v jq >/dev/null || { echo "stale-records.sh: jq is required" >&2; exit 1; }

if [[ -n "${MP_CACERT:-}" ]]; then tls=(--cacert "$MP_CACERT"); else tls=(-k); fi

read -r -d '' SQL <<'SQL' || true
WITH ident AS (
  SELECT h.hostkey, h.hostname, h.ipaddress,
         h.firstreporttimestamp AS firstseen,
         h.lastreporttimestamp  AS lastseen,
         upper(trim(v.variablevalue)) AS uuid
  FROM hosts h
  JOIN variables v ON v.hostkey = h.hostkey
  WHERE v.variablename = 'dmi[system-uuid]'
    AND trim(v.variablevalue) NOT IN ('', '0', 'Not Settable', 'Not Specified')
    AND upper(trim(v.variablevalue)) NOT IN ('00000000-0000-0000-0000-000000000000',
                                             'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF')
),
ranked AS (
  SELECT *, row_number() OVER (PARTITION BY uuid
                               ORDER BY firstseen DESC, lastseen DESC, hostkey) AS rn
  FROM ident
)
SELECT s.hostkey AS stale, c.hostkey AS current, c.hostname, c.ipaddress
FROM ranked c
JOIN ranked s ON s.uuid = c.uuid AND s.rn > 1
WHERE c.rn = 1
  AND s.lastseen <= c.firstseen
ORDER BY c.hostname, s.lastseen
SQL

body=$(jq -n --arg q "$SQL" '{query: $q}')
resp=$(curl -sS --fail-with-body "${tls[@]}" \
         --netrc-file <(printf 'machine %s login %s password %s\n' \
                          "$(sed -E 's#^[a-z]+://##; s#[:/].*##' <<<"$MP_URL")" \
                          "$MP_USER" "$MP_PASSWORD") \
         -H 'Content-Type: application/json' \
         --data-binary "$body" "${MP_URL%/}/api/query") || {
  echo "stale-records.sh: query failed: $resp" >&2; exit 2; }

jq -r '.data[0].rows[] | map(. // "") | join(",")' <<<"$resp"
