Script works against the live hub. It printed 4 unhealthy hosts across 3 categories (matching `/status`'s `totalFailed: 4`), with only the requested output on stdout — the certificate warning goes to stderr.

**Output:**
```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
```

It queries `/api/health-diagnostic/status`, takes its keys minus `total`/`totalFailed` as the category list (so it doesn't miss `hostsUsingSameName`, which `report_ids` omits), then fetches each category's report and emits `<category>,<hostkey>` using each row's first column (`key`), which is the hostkey across all categories.

```bash
#!/usr/bin/env bash
#
# List the hosts currently flagged as unhealthy on Mission Portal's Health
# page. Prints one "<category>,<hostkey>" line per flagged host on stdout.
#
# Requires: curl, jq
#
# Configuration (environment variables):
#   MP_URL       Base URL of the hub's Mission Portal, e.g. https://hub.example.com
#   MP_USER      API user name
#   MP_PASSWORD  API user password
#   MP_CACERT    Optional path to the hub's CA/server certificate for curl's
#                --cacert. If unset, certificate verification is skipped
#                (-k), since the hub is documented to use a self-signed cert.

set -euo pipefail

: "${MP_URL:?MP_URL must be set to the Mission Portal base URL}"
: "${MP_USER:?MP_USER must be set to the API user name}"
: "${MP_PASSWORD:?MP_PASSWORD must be set to the API user password}"

base_url="${MP_URL%/}"

curl_opts=(-s -u "${MP_USER}:${MP_PASSWORD}")
if [ -n "${MP_CACERT:-}" ]; then
    curl_opts+=(--cacert "${MP_CACERT}")
else
    curl_opts+=(-k)
    echo "unhealthy-hosts.sh: MP_CACERT not set, skipping certificate verification (-k)" >&2
fi

fail() {
    echo "unhealthy-hosts.sh: $*" >&2
    exit 1
}

do_get() {
    local path="$1"
    local resp status body
    resp=$(curl "${curl_opts[@]}" -w '\n%{http_code}' "${base_url}${path}") || fail "request to ${path} failed"
    status=${resp##*$'\n'}
    body=${resp%$'\n'*}
    [ "$status" -ge 200 ] && [ "$status" -lt 300 ] || fail "GET ${path} returned HTTP ${status}: ${body}"
    printf '%s' "$body"
}

do_post() {
    local path="$1" data="$2"
    local resp status body
    resp=$(curl "${curl_opts[@]}" -w '\n%{http_code}' \
        -H 'Content-Type: application/json' -X POST -d "$data" "${base_url}${path}") \
        || fail "request to ${path} failed"
    status=${resp##*$'\n'}
    body=${resp%$'\n'*}
    [ "$status" -ge 200 ] && [ "$status" -lt 300 ] || fail "POST ${path} returned HTTP ${status}: ${body}"
    printf '%s' "$body"
}

status_json=$(do_get /api/health-diagnostic/status)

categories=$(printf '%s' "$status_json" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

while IFS= read -r category; do
    [ -n "$category" ] || continue
    report_json=$(do_post "/api/health-diagnostic/report/${category}" '{"limit":10000}')
    printf '%s' "$report_json" | jq -r --arg category "$category" \
        '.data[0].rows[]? | "\($category),\(.[0])"'
done <<< "$categories"
```

Notes:
- It skips TLS verification by default (`-k`) since the hub uses a self-signed certificate; set `MP_CACERT` to the hub's certificate path to verify properly instead.
- Requires `curl` and `jq` on the machine running it.