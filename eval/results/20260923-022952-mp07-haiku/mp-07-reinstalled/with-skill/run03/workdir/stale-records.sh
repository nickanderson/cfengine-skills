#!/bin/bash
set -euo pipefail

MP_API="${MP_API:-/tmp/cfeval-mp-07-reinstalled-with-skill.5iV2KMAp/config/skills/scripts/mp-api.sh}"

# Query: find hosts with same hostname, rank by last report time
# The most recent one per hostname is current; others are stale
read -r -d '' sql <<'SQL' || true
WITH hosts_with_rank AS (
  SELECT
    hostkey,
    hostname,
    ipaddress,
    lastreporttimestamp,
    ROW_NUMBER() OVER (PARTITION BY hostname ORDER BY lastreporttimestamp DESC) as rn
  FROM hosts
  WHERE hostname IS NOT NULL
)
SELECT
  h_stale.hostkey,
  h_current.hostkey,
  h_stale.hostname,
  h_stale.ipaddress
FROM hosts_with_rank h_stale
JOIN hosts_with_rank h_current ON h_stale.hostname = h_current.hostname
WHERE h_stale.rn > 1
AND h_current.rn = 1
ORDER BY h_stale.hostname, h_stale.hostkey
SQL

# Query the API and extract results
"$MP_API" POST /api/query "$(printf '{"query": %s}' "$(jq -Rs . <<< "$sql")")" | \
  jq -r '.data[0].rows[]? | @csv' | \
  sed 's/"//g'
