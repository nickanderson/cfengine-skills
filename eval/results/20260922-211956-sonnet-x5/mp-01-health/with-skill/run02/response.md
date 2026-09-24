Counts match exactly: 1 deletedHostsReport + 2 hostsUsingSameName + 1 agentNotRunRecently = 4 = `totalFailed`, and that's exactly what the script printed.

## Output

```
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
```

## Script

```bash
#!/usr/bin/env bash
#
# Print one line per host flagged unhealthy on Mission Portal's Health page:
#   <category>,<hostkey>
#
# Requires: curl, jq
#
# Configuration (environment variables):
#   MP_URL       Mission Portal base URL, e.g. https://hub.example.com  (required)
#   MP_USER      API username                                           (required)
#   MP_PASSWORD  API password                                           (required)
#   MP_CACERT    Path to a CA certificate file to verify the hub with.
#                If unset, certificate verification is skipped (-k),
#                which is appropriate only for a hub with a self-signed
#                certificate that you already trust.

set -euo pipefail

: "${MP_URL:?Set MP_URL to the Mission Portal base URL, e.g. https://hub.example.com}"
: "${MP_USER:?Set MP_USER to the Mission Portal API username}"
: "${MP_PASSWORD:?Set MP_PASSWORD to the Mission Portal API password}"

MP_URL="${MP_URL%/}"

# Bare hostname (no scheme, no port, no path), for the netrc "machine" line.
MP_HOST="${MP_URL#*://}"
MP_HOST="${MP_HOST%%/*}"
MP_HOST="${MP_HOST%%:*}"

CURL_CERT_OPTS=(-k)
if [ -n "${MP_CACERT:-}" ]; then
    CURL_CERT_OPTS=(--cacert "$MP_CACERT")
fi

netrc() {
    printf 'machine %s login %s password %s\n' "$MP_HOST" "$MP_USER" "$MP_PASSWORD"
}

# api METHOD PATH [JSON-BODY]
api() {
    local method="$1" path="$2" body="${3:-}"
    if [ -n "$body" ]; then
        curl -sS -f "${CURL_CERT_OPTS[@]}" --netrc-file <(netrc) \
            -X "$method" "$MP_URL$path" \
            -H 'Content-Type: application/json' \
            --data-binary "$body"
    else
        curl -sS -f "${CURL_CERT_OPTS[@]}" --netrc-file <(netrc) \
            -X "$method" "$MP_URL$path"
    fi
}

status=$(api GET /api/health-diagnostic/status)

categories=$(printf '%s' "$status" | jq -r \
    'to_entries[] | select(.key != "total" and .key != "totalFailed") | .key')

while IFS= read -r category; do
    [ -n "$category" ] || continue

    skip=0
    limit=10000
    while :; do
        page=$(api POST "/api/health-diagnostic/report/$category" \
            "$(jq -n --argjson skip "$skip" --argjson limit "$limit" \
                '{skip: $skip, limit: $limit}')")

        rows=$(printf '%s' "$page" | jq -r '.data[0].rows // [] | length')
        printf '%s' "$page" | jq -r --arg category "$category" \
            '.data[0].rows // [] | .[] | "\($category),\(.[0])"'

        [ "$rows" -lt "$limit" ] && break
        skip=$((skip + limit))
    done
done <<< "$categories"
```

Notes:
- It derives the health-page categories from `/api/health-diagnostic/status` (excluding `total`/`totalFailed`) rather than `report_ids`, since `report_ids` is known to omit `hostsUsingSameName` on this hub version.
- Uses the report's first column (`key`) as the hostkey per row, and pages with `skip`/`limit` in case any category exceeds 10,000 rows.
- Credentials go through curl's `--netrc-file` (via process substitution) so they never appear in `ps` output; certificate verification is skipped (`-k`) unless `MP_CACERT` is set, since the hub uses a self-signed certificate.