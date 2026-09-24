#!/usr/bin/env bash
# Find leftover host key records from reinstalled machines in CFEngine Mission Portal
# Output format: <stale hostkey>,<current hostkey>,<hostname>,<ip>

set -euo pipefail

# Configuration from environment
MP_URL="${MP_URL:?Mission Portal URL not set}"
MP_USER="${MP_USER:?Mission Portal user not set}"
MP_PASSWORD="${MP_PASSWORD:?Mission Portal password not set}"

# TLS configuration - skip verification by default (self-signed certificates)
# Set MP_CACERT to point to the hub's certificate file to verify instead
tls=(-k)
if [ -n "${MP_CACERT:-}" ]; then
    tls=(--cacert "$MP_CACERT")
fi

# Query all hosts with their last activity timestamp (as epoch seconds for proper sorting)
query='SELECT h.hostkey, h.hostname, h.ipaddress, EXTRACT(EPOCH FROM COALESCE(a.lastagentlocalexecutiontimestamp, h.lastreporttimestamp)) as last_activity FROM hosts h LEFT JOIN agentstatus a ON h.hostkey = a.hostkey ORDER BY h.hostname, h.ipaddress, last_activity DESC'

# Create request body
body=$(jq -n --arg q "$query" '{query: $q}')

# Execute query against Mission Portal
response=$(
    printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" | \
    curl -sS --fail-with-body "${tls[@]}" -K - -X POST \
        -H 'Content-Type: application/json' \
        --data-binary "$body" \
        "$MP_URL/api/query"
)

# Process response to identify and output stale records
# For each hostname+ipaddress combination with multiple hostkeys,
# the most recent one is current; others are stale
echo "$response" | jq -r '
  .data[0].rows as $rows |

  # Convert to objects for easier processing
  ($rows | map({
    hostkey: .[0],
    hostname: .[1],
    ipaddress: .[2],
    activity: (.[3] // 0)
  })) |

  # Group by hostname|ipaddress combination
  group_by(.hostname + "|" + .ipaddress) |

  # Keep only groups with duplicates (multiple hostkeys for same hostname+ip)
  map(select(length > 1)) |

  # Process each duplicate group
  .[] |
  (sort_by(.activity) | reverse) as $sorted |

  # First is current, output the rest as stale
  ($sorted[0]) as $current |
  $sorted[1:][] |
  "\(.hostkey),\($current.hostkey),\(.hostname),\(.ipaddress)"
'
