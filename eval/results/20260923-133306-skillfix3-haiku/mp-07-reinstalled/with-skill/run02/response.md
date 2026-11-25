## Summary

I've created **stale-records.sh**, an executable script that identifies leftover host key records from reinstalled CFEngine machines in the Mission Portal.

### How it works:
1. Queries the Mission Portal API for all hosts and their last activity times
2. Groups hosts by hostname+ipaddress combination
3. For each group with multiple hostkeys, identifies the most recently active one as current
4. Outputs all other hostkeys in that group as stale records

### Output from the hub:

```
SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5,host004.example.com,192.168.56.6
```

This shows that **host004.example.com** at IP 192.168.56.6 was reinstalled with a new hostkey (`SHA=06791f...`), and the old hostkey record (`SHA=714a84...`) is stale and can be cleaned up.

### The complete script:

```bash
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
```

The script requires `MP_URL`, `MP_USER`, and `MP_PASSWORD` environment variables. It skips TLS certificate verification by default (self-signed certs); set `MP_CACERT` to verify against the hub's certificate file.