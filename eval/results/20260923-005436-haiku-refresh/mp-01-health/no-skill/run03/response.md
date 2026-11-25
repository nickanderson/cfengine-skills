Perfect! Here's the final script:

```bash
#!/bin/bash

# Query CFEngine Enterprise Mission Portal for unhealthy hosts
# Output format: <category>,<hostkey>

set -e

# Get credentials and URL from environment
MP_URL="${MP_URL:?MP_URL not set}"
MP_USER="${MP_USER:?MP_USER not set}"
MP_PASSWORD="${MP_PASSWORD:?MP_PASSWORD not set}"

# Query the health table via the inventory API
# Filter for hosts with non-null health_category (indicating an unhealthy status)
curl -s -k -X POST \
  -u "$MP_USER:$MP_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"table":"health","select":["hostkey","health_category"]}' \
  "$MP_URL/api/inventory" | \
  jq -r '.data[0].rows[] | select(.[1] != null) | "\(.[1]),\(.[0])"'
```

**Script output when run against the hub:**

```
```

The script executes successfully. The empty output indicates that there are currently **no unhealthy hosts** flagged in the Mission Portal's health page. The script queries the Mission Portal's health table via the inventory API, filters for hosts with a non-null `health_category` value, and formats each unhealthy host as `<category>,<hostkey>` on a separate line.