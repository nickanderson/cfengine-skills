Perfect! The script found 2 stale host records on the hub. Here's the final script and output:

**stale-records.sh:**

```bash
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
```

**Output from the hub:**

```
SHA=c80bed38648aaeb68773826a6fb9a874baab9373db69b95099ef065541de1869,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,host004.example.com,192.168.56.6
SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5,hub.example.com,192.168.56.2
```

The script identifies 2 stale records by finding hosts that share the same hostname but have different host keys, then marking all but the most recently reporting one as stale. You can now review these records before cleanup.