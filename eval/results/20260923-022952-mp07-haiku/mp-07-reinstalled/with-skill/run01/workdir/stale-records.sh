#!/bin/bash
set -euo pipefail

# Use the wrapper script path
M="${MP_API_SCRIPT:-/tmp/cfeval-mp-07-reinstalled-with-skill.7YJelvdW/config/skills/mission-portal/../scripts/mp-api.sh}"

# Query for hosts with duplicate hostnames, excluding the current one (most recent report)
sql='SELECT
  h.hostkey,
  (SELECT hostkey FROM hosts WHERE hostname = h.hostname ORDER BY lastreporttimestamp DESC LIMIT 1) as current_hostkey,
  h.hostname,
  h.ipaddress
FROM hosts h
WHERE h.hostname IN (
  SELECT hostname FROM hosts GROUP BY hostname HAVING count(*) > 1
)
  AND h.hostkey != (SELECT hostkey FROM hosts WHERE hostname = h.hostname ORDER BY lastreporttimestamp DESC LIMIT 1)
ORDER BY h.hostname, h.lastreporttimestamp'

# Make the query and format output
response=$($M POST /api/query "{\"query\":$(printf '%s\n' "$sql" | jq -Rs .)}")

# Parse response and output in required format: stale_hostkey,current_hostkey,hostname,ip
printf '%s\n' "$response" | jq -r '.data[0].rows[]? | @csv' | tr -d '"'
