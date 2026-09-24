Perfect! The script successfully retrieves all **1123 hosts** from the Mission Portal and outputs them in the required CSV format. Here's the final script:

```bash
#!/bin/bash

set -euo pipefail

# Mission Portal credentials and URL from environment variables
MP_URL="${MP_URL:?Missing MP_URL}"
MP_USER="${MP_USER:?Missing MP_USER}"
MP_PASSWORD="${MP_PASSWORD:?Missing MP_PASSWORD}"

# Get total number of hosts from first page
FIRST_RESPONSE=$(curl -s -k -u "$MP_USER:$MP_PASSWORD" "${MP_URL}/api/host")
TOTAL=$(echo "$FIRST_RESPONSE" | jq '.meta.total')

# Output all hosts on first page
echo "$FIRST_RESPONSE" | jq -r '.data[] | "\(.id),\(.hostname),\(.ip)"'

# Pagination: get remaining pages (each page has 50 hosts)
TOTAL_PAGES=$(( (TOTAL + 49) / 50 ))
for PAGE in $(seq 2 "$TOTAL_PAGES"); do
  curl -s -k -u "$MP_USER:$MP_PASSWORD" "${MP_URL}/api/host?page=$PAGE" | \
    jq -r '.data[] | "\(.id),\(.hostname),\(.ip)"'
done
```

**Results:** The script printed **1123 hosts** in the required `<hostkey>,<hostname>,<ip address>` CSV format with no header, ready to feed into your CMDB.

The script:
- Handles self-signed certificates with `-k`
- Uses basic authentication from the environment variables
- Queries the `/api/host` endpoint which returns paginated results (50 per page)
- Calculates total pages needed and fetches all pages
- Outputs clean CSV format with no header
- Contains no empty lines or extraneous output