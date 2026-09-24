Perfect! The script found the stale records. Here's the final script:

```bash
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
```

**Output against your hub:**

```
SHA=c80bed38648aaeb68773826a6fb9a874baab9373db69b95099ef065541de1869,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,host004.example.com,192.168.56.6
SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5,hub.example.com,192.168.56.2
```

The script finds hosts with identical hostnames but different hostkeys (a sign of reinstallation), identifies the current record based on most recent report time, and lists all the stale ones.