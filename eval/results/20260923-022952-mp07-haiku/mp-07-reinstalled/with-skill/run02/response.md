Perfect! The script found one stale host record. Here's the complete script:

```bash
#!/bin/bash
set -euo pipefail

# Find leftover host records from reinstalled machines
# Output: <stale hostkey>,<current hostkey>,<hostname>,<ip>
# One line per stale record

MP_WRAPPER="${MP_WRAPPER:-/tmp/cfeval-mp-07-reinstalled-with-skill.2YrGyYSW/config/skills/scripts/mp-api.sh}"

if [[ ! -x "$MP_WRAPPER" ]]; then
    echo "Error: mp-api.sh not found at $MP_WRAPPER" >&2
    exit 1
fi

# Query for all hosts with their details
query='SELECT hostkey, hostname, ipaddress, lastreporttimestamp FROM hosts ORDER BY hostname, ipaddress, lastreporttimestamp DESC'

response=$("$MP_WRAPPER" POST /api/query "$(jq -n --arg q "$query" '{query: $q}')" 2>/dev/null)

if [[ -z "$response" ]]; then
    echo "Error: Failed to query Mission Portal" >&2
    exit 1
fi

# Extract and process results
echo "$response" | jq -r '.data[0].rows[] | @csv' | while IFS=',' read -r hostkey hostname ipaddress timestamp; do
    # Remove quotes added by @csv
    hostkey="${hostkey%\"}"
    hostkey="${hostkey#\"}"
    hostname="${hostname%\"}"
    hostname="${hostname#\"}"
    ipaddress="${ipaddress%\"}"
    ipaddress="${ipaddress#\"}"
    timestamp="${timestamp%\"}"
    timestamp="${timestamp#\"}"
    
    echo "$hostkey|$hostname|$ipaddress|$timestamp"
done | awk -F'|' '
BEGIN { current_group = ""; current_hostkey = ""; current_ip = ""; current_timestamp = 0 }
{
    hostkey = $1; hostname = $2; ip = $3; timestamp = $4
    group = hostname ":" ip
    
    if (group != current_group) {
        # Process previous group
        if (current_group != "" && length(hosts) > 0) {
            stale_keys = ""
            for (h in hosts) {
                if (h != current_hostkey) {
                    stale_keys = (stale_keys == "" ? h : stale_keys "\n" h)
                }
            }
            if (stale_keys != "") {
                n = split(stale_keys, arr, "\n")
                for (i = 1; i <= n; i++) {
                    print arr[i] "," current_hostkey "," current_group_hostname "," current_group_ip
                }
            }
        }
        
        # Start new group
        current_group = group
        split(group, parts, ":")
        current_group_hostname = parts[1]
        current_group_ip = parts[2]
        delete hosts
        current_hostkey = hostkey
        current_timestamp = timestamp
        hosts[hostkey] = 1
    } else {
        # Same group - add to hosts list
        hosts[hostkey] = 1
    }
}
END {
    # Process final group
    if (current_group != "" && length(hosts) > 0) {
        stale_keys = ""
        for (h in hosts) {
            if (h != current_hostkey) {
                stale_keys = (stale_keys == "" ? h : stale_keys "\n" h)
            }
        }
        if (stale_keys != "") {
            n = split(stale_keys, arr, "\n")
            for (i = 1; i <= n; i++) {
                print arr[i] "," current_hostkey "," current_group_hostname "," current_group_ip
            }
        }
    }
}
'
```

## Output

```
SHA=c80bed38648aaeb68773826a6fb9a874baab9373db69b95099ef065541de1869,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,host004.example.com,192.168.56.6
```

The script found **one stale record**: host004.example.com (192.168.56.6) has an old host key that should be cleaned up. The current host key for that machine is SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4.