#!/usr/bin/env bash
# stale-records.sh
#
# Finds Mission Portal host records left behind by machines that were
# reinstalled (and so now report under a new CFEngine host key, while the
# hub still keeps the old key's record).
#
# For every (hostname) shared by more than one live host record, the record
# whose last report is close to "now" (within its own learned reporting
# cadence) is treated as the machine's *current* identity; any other record
# for that same hostname whose last report has fallen far behind that
# current record's is treated as a *stale* leftover from a reinstall.
#
# Output: one line per leftover record, and nothing else on stdout:
#   <stale hostkey>,<current hostkey>,<hostname>,<ip>
#
# Read-only: issues a single SELECT via POST /api/query. Nothing is deleted.
#
# Required environment:
#   MP_URL       Mission Portal base URL, e.g. https://192.168.56.2
#   MP_USER      Mission Portal username
#   MP_PASSWORD  Mission Portal password
# Optional:
#   MP_CACERT    Path to the hub's CA/server certificate, for verified TLS.
#                If unset, certificate verification is skipped (-k), since
#                Mission Portal hubs commonly use a self-signed certificate.

set -u -o pipefail

: "${MP_URL:?MP_URL is not set}"
: "${MP_USER:?MP_USER is not set}"
: "${MP_PASSWORD:?MP_PASSWORD is not set}"

base_url="${MP_URL%/}"

if [ -n "${MP_CACERT:-}" ]; then
    curl_tls_opts=(--cacert "${MP_CACERT}")
else
    curl_tls_opts=(-k)
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "stale-records.sh: jq is required but not found in PATH" >&2
    exit 3
fi

# One row per record still sharing a hostname with the current, live
# identity for that host, whose own last report has fallen behind that
# current identity's by more than its normal reporting cadence
# (GREATEST(600s, 1.3x its learned agent-execution interval) -- the same
# floor Mission Portal's own "outdated reporting data" health check uses).
read -r -d '' sql <<'SQL'
WITH h AS (
  SELECT hosts.hostkey AS hostkey,
         hosts.hostname AS hostname,
         hosts.ipaddress AS ipaddress,
         hosts.lastreporttimestamp::timestamptz AS lastreport,
         COALESCE(agentstatus.agentexecutioninterval::numeric, 300) AS interval
  FROM hosts
  LEFT JOIN agentstatus ON agentstatus.hostkey = hosts.hostkey
),
grp AS (
  SELECT hostname, MAX(lastreport) AS max_last
  FROM h
  GROUP BY hostname
  HAVING COUNT(*) > 1
)
SELECT h.hostkey AS stale_hostkey,
       cur.hostkey AS current_hostkey,
       h.hostname AS hostname,
       cur.ipaddress AS ip
FROM h
JOIN grp ON grp.hostname = h.hostname
JOIN h cur ON cur.hostname = h.hostname AND cur.lastreport = grp.max_last
WHERE h.hostkey <> cur.hostkey
  AND extract(epoch FROM (grp.max_last - h.lastreport)) > GREATEST(600, h.interval * 1.3)
  AND extract(epoch FROM (now() - grp.max_last)) <= GREATEST(600, cur.interval * 1.3)
SQL

body=$(jq -n --arg q "$sql" '{query: $q}')

# Strip scheme and any path/port suffix to get the bare host curl's netrc
# machine matching needs.
host_no_scheme="${base_url#*://}"
host_only="${host_no_scheme%%/*}"
host_only="${host_only%%:*}"

response=$(curl -sS --fail-with-body "${curl_tls_opts[@]}" \
        --netrc-file <(printf 'machine %s\nlogin %s\npassword %s\n' \
            "$host_only" "$MP_USER" "$MP_PASSWORD") \
        -H 'Content-Type: application/json' \
        -X POST "$base_url/api/query" \
        --data-binary "$body")
status=$?

if [ "$status" -ne 0 ]; then
    echo "stale-records.sh: request to $base_url/api/query failed" >&2
    echo "$response" >&2
    exit "$status"
fi

echo "$response" | jq -r '.data[0].rows[]? | join(",")'
