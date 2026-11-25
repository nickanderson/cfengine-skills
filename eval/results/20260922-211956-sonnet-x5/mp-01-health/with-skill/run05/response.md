The script queries `/api/health-diagnostic/status` for the list of health categories, then pulls each category's report (`/api/health-diagnostic/report/:category`) and emits `<category>,<hostkey>` for every row, using the first column (`key`) as the hostkey per the skill's guidance (report columns vary, but that first column is consistently the hostkey).

Run against the hub, it printed:

```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
```

This matches the hub's own tally (`totalFailed: 4`). Note it skips TLS verification (`-k`) since no CA file was supplied — set `MP_CACERT` to the hub's certificate for real verification.

```bash
#!/usr/bin/env bash
#
# Print one line per host flagged unhealthy on Mission Portal's Health page:
#   <category>,<hostkey>
#
# Required environment:
#   MP_URL       Mission Portal base URL, e.g. https://hub.example.com
#   MP_USER      API user name
#   MP_PASSWORD  API user password
# Optional:
#   MP_CACERT    Path to the hub's CA/certificate to verify against.
#                If unset, certificate verification is skipped (-k), which
#                is needed for a self-signed hub certificate.

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

for cmd in curl jq; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "unhealthy-hosts.sh: $cmd is required" >&2; exit 1; }
done

curl_tls_args=()
if [ -n "${MP_CACERT:-}" ]; then
    curl_tls_args=(--cacert "$MP_CACERT")
else
    curl_tls_args=(-k)
fi

netrc=$(mktemp)
trap 'rm -f "$netrc"' EXIT
host_only=$(printf '%s' "$MP_URL" | sed -E 's#^[a-zA-Z]+://##; s#/.*$##; s#:.*$##')
printf 'machine %s login %s password %s\n' "$host_only" "$MP_USER" "$MP_PASSWORD" > "$netrc"

status=$(curl -sS "${curl_tls_args[@]}" --netrc-file "$netrc" "$MP_URL/api/health-diagnostic/status")

categories=$(printf '%s' "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

while IFS= read -r category; do
    [ -n "$category" ] || continue
    report=$(curl -sS "${curl_tls_args[@]}" --netrc-file "$netrc" \
        -H 'Content-Type: application/json' \
        -d '{"limit": 10000}' \
        "$MP_URL/api/health-diagnostic/report/$category")

    printf '%s' "$report" | jq -r --arg category "$category" \
        '.data[0].rows[]? | "\($category),\(.[0])"'
done <<< "$categories"
```