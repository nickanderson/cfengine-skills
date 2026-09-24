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
