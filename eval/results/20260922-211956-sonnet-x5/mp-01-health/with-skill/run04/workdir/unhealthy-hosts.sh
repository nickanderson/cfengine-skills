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
