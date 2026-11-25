#!/usr/bin/env bash
# stale-records.sh - list Mission Portal host records left behind by
# reinstalled machines (machine came back with a new host key).
#
# Prints one line per leftover record:
#   <stale hostkey>,<current hostkey>,<hostname>,<ip>
#
# A record is "leftover" when another record with the same hostname first
# reported *after* it last reported, i.e. the old identity went silent and a
# new one took its place. Records that are both still reporting (two live
# machines sharing a name) are not matched. The current record is the newest
# surviving identity for that hostname, preferring one on the same IP.
# Hostname and IP printed are those the machine reports now. Read-only.
#
# Environment: MP_URL, MP_USER, MP_PASSWORD (required)
#              MP_CACERT (optional; hub CA/cert file; without it TLS
#              verification is skipped, since the hub cert is self-signed)
set -euo pipefail

: "${MP_URL:?MP_URL not set}" "${MP_USER:?MP_USER not set}" "${MP_PASSWORD:?MP_PASSWORD not set}"
command -v jq >/dev/null || { echo "stale-records.sh: jq is required" >&2; exit 1; }

if [ -n "${MP_CACERT:-}" ]; then tls=(--cacert "$MP_CACERT"); else tls=(-k); fi

read -r -d '' SQL <<'SQL' || true
WITH h AS (
  SELECT hostkey, lower(hostname) AS name, hostname, ipaddress,
         firstreporttimestamp AS f, lastreporttimestamp AS l
  FROM hosts
  WHERE hostname IS NOT NULL AND hostname <> ''
),
superseded AS (
  SELECT s.* FROM h s
  WHERE EXISTS (SELECT 1 FROM h x
                WHERE x.name = s.name AND x.hostkey <> s.hostkey AND x.f > s.l)
),
current AS (
  SELECT * FROM h WHERE hostkey NOT IN (SELECT hostkey FROM superseded)
)
SELECT DISTINCT ON (s.hostkey)
       s.hostkey AS stale, c.hostkey AS current, c.hostname, c.ipaddress
FROM superseded s
JOIN current c ON c.name = s.name AND c.f > s.l
ORDER BY s.hostkey, (c.ipaddress IS NOT DISTINCT FROM s.ipaddress) DESC, c.l DESC, c.f DESC
SQL

body=$(jq -n --arg q "$SQL" '{query: $q}')
host=$(printf '%s' "$MP_URL" | sed -E 's#^[a-z]+://##; s#[/:].*$##')

resp=$(printf '%s' "$body" | curl -sS --fail-with-body "${tls[@]}" \
  --netrc-file <(printf 'machine %s login %s password %s\n' "$host" "$MP_USER" "$MP_PASSWORD") \
  -H 'Content-Type: application/json' --data-binary @- \
  "${MP_URL%/}/api/query") || { echo "stale-records.sh: query failed: $resp" >&2; exit 2; }

printf '%s' "$resp" | jq -r '.data[0].rows[] | map(. // "") | join(",")'
