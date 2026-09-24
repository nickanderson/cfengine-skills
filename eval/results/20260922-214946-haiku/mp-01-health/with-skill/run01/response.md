Perfect! The script works correctly. Here's the executable script that queries the CFEngine Enterprise hub's Health page via the Mission Portal API:

```bash
#!/bin/bash
set -euo pipefail

if [[ -z "${MP_URL:-}" || -z "${MP_USER:-}" || -z "${MP_PASSWORD:-}" ]]; then
  echo "Error: MP_URL, MP_USER, and MP_PASSWORD must be set" >&2
  exit 1
fi

# Certificate handling: use provided cert or skip verification
CERT_OPTS=(-k)
if [[ -n "${MP_CACERT:-}" ]]; then
  CERT_OPTS=(--cacert "$MP_CACERT")
fi

# Get health status to identify unhealthy categories
status=$(printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" | \
  curl -sS -K - "${CERT_OPTS[@]}" "$MP_URL/api/health-diagnostic/status")

# Extract category names (exclude 'total' and 'totalFailed')
categories=$(echo "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

# Query each category and output unhealthy hosts
for category in $categories; do
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" | \
    curl -sS -K - "${CERT_OPTS[@]}" \
      -H "Content-Type: application/json" \
      -d '{"limit": 10000}' \
      "$MP_URL/api/health-diagnostic/report/$category" | \
    jq -r ".data[0].rows[][0]" | \
    while read -r hostkey; do
      echo "$category,$hostkey"
    done
done
```

## Output from the hub

```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
```

The script:
- Uses the environment variables `MP_URL`, `MP_USER`, and `MP_PASSWORD` for credentials
- Passes credentials via stdin to curl (never in arguments or environment) to avoid exposure
- Skips certificate verification with `-k` by default (certificate is self-signed); optionally accepts `MP_CACERT` for the hub's certificate
- Queries `/api/health-diagnostic/status` to identify all unhealthy categories
- Fetches the report for each category and extracts hostkeys from the first column of each row
- Outputs one line per flagged host in the format `<category>,<hostkey>`