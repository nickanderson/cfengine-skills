The script works and prints exactly the one leftover record on this hub, correctly excluding the `hub.example.com` hostname collision (different IPs, both currently reporting — a genuine naming coincidence, not a reinstall) and the already-deleted host.

**Output from running it against the hub:**
```
SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5,host004.example.com,192.168.56.6
```

**Logic:** groups hosts by `(hostname, ipaddress)`; within any group with more than one record, the one with the most recent `lastreporttimestamp` is treated as the machine's current identity, and every other record in that group is a leftover from before reinstallation. Grouping by IP as well as hostname is what correctly excludes the `hub.example.com` case in this dataset — two different machines that just happen to share a hostname but have different IPs and are both actively reporting, not a reinstall.

```bash
#!/usr/bin/env bash
# Find leftover Mission Portal host records left behind by reinstalled
# machines: same hostname + IP address reporting under an old hostkey that
# has stopped, while a newer hostkey for the same hostname/IP is current.
#
# Needs: MP_URL, MP_USER, MP_PASSWORD
# Optional: MP_CACERT (path to the hub's certificate; otherwise TLS
#           verification is skipped, since the hub uses a self-signed cert)
#
# Prints one CSV line per leftover record on stdout:
#   <stale hostkey>,<current hostkey>,<hostname>,<ip>

set -euo pipefail

: "${MP_URL:?MP_URL is required}"
: "${MP_USER:?MP_USER is required}"
: "${MP_PASSWORD:?MP_PASSWORD is required}"

tls=(-k)
[ -n "${MP_CACERT:-}" ] && tls=(--cacert "$MP_CACERT")

query='WITH ranked AS (
  SELECT hostkey, hostname, ipaddress, lastreporttimestamp,
         ROW_NUMBER() OVER (PARTITION BY hostname, ipaddress ORDER BY lastreporttimestamp DESC) AS rn
  FROM hosts
)
SELECT r2.hostkey AS stale_hostkey, r1.hostkey AS current_hostkey, r1.hostname, r1.ipaddress
FROM ranked r1
JOIN ranked r2 ON r1.hostname = r2.hostname AND r1.ipaddress = r2.ipaddress
WHERE r1.rn = 1 AND r2.rn > 1'

body=$(jq -n --arg q "$query" '{query: $q}')

response=$(printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
  curl -sS --fail-with-body "${tls[@]}" -K - \
    -X POST -H 'Content-Type: application/json' --data-binary "$body" \
    "$MP_URL/api/query")

echo "$response" | jq -r '.data[0].rows[]? | @csv' | tr -d '"'
```

Notes:
- Uses the `hosts` reporting view, which already excludes deleted hosts — so a host that was properly deleted (not reinstalled) is never reported as stale.
- TLS verification is skipped (`-k`) by default since the hub's certificate is self-signed; set `MP_CACERT` to the hub's certificate path to verify properly instead.
- Nothing is deleted; it only reads via `/api/query`.