The script is written to `unhealthy-hosts.sh`, is executable, and verified against the live hub — its 4 output lines match `totalFailed: 4` from `/api/health-diagnostic/status` (1 `agentNotRunRecently` + 1 `deletedHostsReport` + 2 `hostsUsingSameName`).

**Output from running it against the hub:**
```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
```

It reads `MP_URL`/`MP_USER`/`MP_PASSWORD` from the environment (credentials go to curl via a temp netrc file, never as command-line arguments), skips TLS verification with `-k` since the hub uses a self-signed certificate (set `MP_CACERT` to a certificate file to verify properly instead), enumerates categories from `/api/health-diagnostic/status`'s keys (excluding `total`/`totalFailed`), and pages each category's report in batches of 1000 until exhausted, printing `<category>,<hostkey>` (first column of each row) per flagged host.

```bash
#!/usr/bin/env bash
#
# Ask a CFEngine Enterprise Mission Portal hub which hosts its Health page
# currently flags as unhealthy, and print one line per flagged host:
#
#   <category>,<hostkey>
#
# Configuration (environment variables):
#   MP_URL       Mission Portal base URL, e.g. https://hub.example.com (required)
#   MP_USER      API username (required)
#   MP_PASSWORD  API password (required)
#   MP_CACERT    Path to a CA/certificate file to verify the hub's TLS
#                certificate. If unset, certificate verification is skipped
#                (-k), which is appropriate only for a hub known to use a
#                self-signed certificate.

set -euo pipefail

: "${MP_URL:?Set MP_URL to the Mission Portal base URL, e.g. https://hub.example.com}"
: "${MP_USER:?Set MP_USER to the Mission Portal API username}"
: "${MP_PASSWORD:?Set MP_PASSWORD to the Mission Portal API password}"

if ! command -v jq >/dev/null 2>&1; then
    echo "unhealthy-hosts.sh: jq is required but not found in PATH" >&2
    exit 1
fi

mp_url=${MP_URL%/}

curl_tls_opts=(-k)
if [ -n "${MP_CACERT:-}" ]; then
    curl_tls_opts=(--cacert "$MP_CACERT")
fi

netrc_file=$(mktemp)
trap 'rm -f "$netrc_file"' EXIT
host_port=${mp_url#*://}
printf 'machine %s login %s password %s\n' "${host_port%%/*}" "$MP_USER" "$MP_PASSWORD" >"$netrc_file"
chmod 600 "$netrc_file"

# Performs one API call. $1 = HTTP method, $2 = path (starting with /api),
# $3 = optional JSON request body.
mp_api() {
    local method=$1 path=$2 data=${3:-}
    if [ -n "$data" ]; then
        curl -sS --fail-with-body -X "$method" "${curl_tls_opts[@]}" --netrc-file "$netrc_file" \
            -H 'Content-Type: application/json' -d "$data" "$mp_url$path"
    else
        curl -sS --fail-with-body -X "$method" "${curl_tls_opts[@]}" --netrc-file "$netrc_file" \
            "$mp_url$path"
    fi
}

status=$(mp_api GET /api/health-diagnostic/status)

categories=$(printf '%s' "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

while IFS= read -r category; do
    [ -z "$category" ] && continue

    skip=0
    limit=1000
    while :; do
        body=$(jq -n --argjson skip "$skip" --argjson limit "$limit" '{skip: $skip, limit: $limit}')
        response=$(mp_api POST "/api/health-diagnostic/report/$category" "$body")

        row_count=$(printf '%s' "$response" | jq -r '.data[0].rowCount // 0')

        printf '%s' "$response" | jq -r --arg category "$category" \
            '.data[0].rows[]? | [$category, .[0]] | @csv' \
            | tr -d '"'

        if [ "$row_count" -lt "$limit" ]; then
            break
        fi
        skip=$((skip + limit))
    done
done <<<"$categories"
```