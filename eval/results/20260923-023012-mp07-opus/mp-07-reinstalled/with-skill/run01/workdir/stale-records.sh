#!/usr/bin/env bash
# List Mission Portal host records left behind by reinstalled machines.
#
# A reinstalled machine reports under a new host key with the same hostname.
# A record is "stale" when another record with the same hostname first
# reported after the stale one last reported (their lifetimes do not
# overlap). Records with the same hostname that report side by side are
# distinct machines sharing a name, not reinstalls, and are not listed.
#
# Output: <stale hostkey>,<current hostkey>,<hostname>,<ip>  (ip = current)
# Read-only: uses only POST /api/query.
#
# Env: MP_URL, MP_USER, MP_PASSWORD; optional MP_CACERT (hub certificate,
# otherwise certificate verification is skipped with -k).
set -euo pipefail

: "${MP_URL:?MP_URL not set}" "${MP_USER:?MP_USER not set}" "${MP_PASSWORD:?MP_PASSWORD not set}"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

if [ -n "${MP_CACERT:-}" ]; then tls=(--cacert "$MP_CACERT"); else tls=(-k); fi

read -r -d '' SQL <<'SQL' || true
WITH h AS (
  SELECT hostkey, lower(hostname) AS hn, hostname, ipaddress,
         lastreporttimestamp AS lr, firstreporttimestamp AS fr
  FROM hosts
  WHERE hostname IS NOT NULL AND hostname <> ''
),
cur AS (
  SELECT * FROM h
  WHERE NOT EXISTS (SELECT 1 FROM h d
                    WHERE d.hn = h.hn AND d.hostkey <> h.hostkey AND d.fr >= h.lr)
),
pairs AS (
  SELECT DISTINCT ON (s.hostkey)
         s.hostkey AS stale, c.hostkey AS current, c.hostname, c.ipaddress
  FROM h s
  JOIN cur c ON c.hn = s.hn AND c.hostkey <> s.hostkey AND c.fr >= s.lr
  ORDER BY s.hostkey, (c.ipaddress = s.ipaddress) DESC, c.lr DESC
)
SELECT stale, current, hostname, ipaddress FROM pairs ORDER BY hostname, stale
SQL

body=$(jq -n --arg q "$SQL" '{query: $q, limit: 1000000}')

resp=$(curl -sS --fail-with-body "${tls[@]}" \
  --netrc-file <(printf 'machine %s login %s password %s\n' \
      "$(printf '%s' "$MP_URL" | sed -E 's#^[a-z]+://##; s#[:/].*$##')" "$MP_USER" "$MP_PASSWORD") \
  -H 'Content-Type: application/json' \
  --data-binary "$body" "${MP_URL%/}/api/query") || {
  echo "query failed: $resp" >&2; exit 2; }

jq -r '.data[0].rows[] | map(. // "") | join(",")' <<<"$resp"
