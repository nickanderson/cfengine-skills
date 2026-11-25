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
