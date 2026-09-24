#!/usr/bin/env bash
# Prints "<category>,<hostkey>" for every host the Mission Portal Health page
# currently flags as unhealthy.
#
# Required environment:
#   MP_URL       Mission Portal base URL, e.g. https://hub.example.com
#   MP_USER      API username
#   MP_PASSWORD  API password
# Optional:
#   MP_CACERT    Path to the hub's CA certificate. If unset, certificate
#                verification is skipped (-k) -- suitable for a hub with a
#                self-signed certificate.
set -euo pipefail

: "${MP_URL:?Set MP_URL to the Mission Portal base URL}"
: "${MP_USER:?Set MP_USER to the API username}"
: "${MP_PASSWORD:?Set MP_PASSWORD to the API password}"

mp_cert_opts=(-k)
if [ -n "${MP_CACERT:-}" ]; then
  mp_cert_opts=(--cacert "$MP_CACERT")
fi

# host[:port] portion of MP_URL, for the netrc "machine" line
mp_host=$(printf '%s\n' "$MP_URL" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##; s#/.*##')

mp_netrc() {
  printf 'machine %s login %s password %s\n' "$mp_host" "$MP_USER" "$MP_PASSWORD"
}

mp_api() {
  local method=$1 path=$2 body=${3:-}
  if [ -n "$body" ]; then
    curl -sS "${mp_cert_opts[@]}" --netrc-file <(mp_netrc) \
      -X "$method" -H 'Content-Type: application/json' -d "$body" \
      "$MP_URL$path"
  else
    curl -sS "${mp_cert_opts[@]}" --netrc-file <(mp_netrc) \
      -X "$method" \
      "$MP_URL$path"
  fi
}

# report_ids omits at least one category (hostsUsingSameName) on 3.27.1, so
# take the category list from status instead.
status=$(mp_api GET /api/health-diagnostic/status)
categories=$(printf '%s' "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

while IFS= read -r category; do
  [ -n "$category" ] || continue

  skip=0
  limit=1000
  while :; do
    body=$(printf '{"skip":%d,"limit":%d}' "$skip" "$limit")
    resp=$(mp_api POST "/api/health-diagnostic/report/$category" "$body")

    # The first column ("key") is the hostkey in every category's report,
    # even though the remaining columns differ per category.
    printf '%s' "$resp" | jq -r --arg cat "$category" \
      '.data[0].rows[]? | [$cat, .[0]] | @csv' | tr -d '"'

    rowCount=$(printf '%s' "$resp" | jq -r '.data[0].rowCount // 0')
    [ "$rowCount" -lt "$limit" ] && break
    skip=$((skip + limit))
  done
done <<< "$categories"
