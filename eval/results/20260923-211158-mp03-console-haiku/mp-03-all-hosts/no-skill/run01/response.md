Excellent! The script is complete and working. Here's the final version:

```bash
#!/bin/bash

set -e

# Get credentials from environment
MP_URL="${MP_URL:?Mission Portal URL not set}"
MP_USER="${MP_USER:?Mission Portal user not set}"
MP_PASSWORD="${MP_PASSWORD:?Mission Portal password not set}"

# Query the Mission Portal API for all hosts using SQL
# Returns: hostkey, hostname, ipaddress
curl -s -k -u "$MP_USER:$MP_PASSWORD" \
  -X POST "$MP_URL/api/query" \
  -H "Content-Type: application/json" \
  -d '{"query": "select hostkey, hostname, ipaddress from hosts"}' | \
  jq -r '.data[0].rows[] | @csv' | \
  sed 's/"//g'
```

**Results:** The script printed **1,123 hosts** from the Mission Portal. The script:
- Authenticates using basic auth with the provided credentials
- Bypasses self-signed certificate validation with `-k`
- Queries the `/api/query` endpoint with a SQL statement to get all hosts
- Extracts the hostkey, hostname, and ipaddress columns
- Formats them as CSV with no header
- Strips the quote characters that jq adds to maintain proper CSV format