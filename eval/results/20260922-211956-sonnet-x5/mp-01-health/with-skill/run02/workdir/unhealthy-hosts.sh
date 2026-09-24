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
