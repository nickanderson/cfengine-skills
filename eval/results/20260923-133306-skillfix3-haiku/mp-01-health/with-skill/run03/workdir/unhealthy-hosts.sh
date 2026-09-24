#!/usr/bin/env bash
set -euo pipefail

# Requires: MP_URL, MP_USER, MP_PASSWORD
# Optional: MP_CACERT (path to hub's certificate; if not provided, skips verification)

MP_URL="${MP_URL:?MP_URL environment variable not set}"
MP_USER="${MP_USER:?MP_USER environment variable not set}"
MP_PASSWORD="${MP_PASSWORD:?MP_PASSWORD environment variable not set}"

# TLS options: use provided certificate or skip verification for self-signed
if [ -n "${MP_CACERT:-}" ]; then
    TLS_OPTS=(--cacert "$MP_CACERT")
else
    TLS_OPTS=(-k)
fi

# Helper to call Mission Portal API
mp_api() {
    local method="$1"
    local path="$2"
    local body="${3:-}"

    local -a opts=(
        -sS --fail-with-body
        "${TLS_OPTS[@]}"
        -X "$method"
    )

    if [ -n "$body" ]; then
        opts+=(-H 'Content-Type: application/json' --data-binary "$body")
    fi

    # Basic auth via Authorization header
    local auth
    auth=$(printf '%s:%s' "$MP_USER" "$MP_PASSWORD" | base64 -w0)
    opts+=(-H "Authorization: Basic $auth")

    curl "${opts[@]}" "$MP_URL$path"
}

# Get all health diagnostic categories
status=$(mp_api GET '/api/health-diagnostic/status')

# Extract category names, excluding metadata fields
categories=$(echo "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

# Query each category and output hostkeys
for category in $categories; do
    report=$(mp_api POST "/api/health-diagnostic/report/$category" '{"limit": 10000}')

    # Extract hostkey (first element of each row) and output category,hostkey
    echo "$report" | jq -r '.data[0].rows[] | .[0]' | while read -r hostkey; do
        [ -n "$hostkey" ] && echo "$category,$hostkey"
    done
done
