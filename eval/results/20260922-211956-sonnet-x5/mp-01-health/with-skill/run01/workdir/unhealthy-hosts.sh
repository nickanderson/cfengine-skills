#!/usr/bin/env bash
#
# Ask a CFEngine Enterprise Mission Portal hub which hosts its Health page
# currently flags as unhealthy, and print one line per flagged host:
#
#   <category>,<hostkey>
#
# Configuration (environment variables):
#   MP_URL       Base URL of the hub, e.g. https://192.168.56.2   (required)
#   MP_USER      API username                                     (required)
#   MP_PASSWORD  API password                                     (required)
#   MP_CACERT    Path to a CA/certificate file to verify the hub's
#                certificate. If unset, certificate verification is
#                skipped (-k) -- suitable for a hub with a self-signed
#                certificate that you have not exported.
#
set -euo pipefail

: "${MP_URL:?MP_URL is not set}"
: "${MP_USER:?MP_USER is not set}"
: "${MP_PASSWORD:?MP_PASSWORD is not set}"

for cmd in curl jq; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "unhealthy-hosts.sh: '$cmd' is required but not installed" >&2; exit 1; }
done

base_url=${MP_URL%/}

if [ -n "${MP_CACERT:-}" ]; then
    tls_args=(--cacert "$MP_CACERT")
else
    tls_args=(-k)
fi

# Credentials go to curl via a config file on stdin, so they never appear as
# a command-line argument (visible in `ps`) or in this script's own output.
netrc_config() {
    printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD"
}

api_get() {
    netrc_config | curl -sS -K - "${tls_args[@]}" "$base_url$1"
}

api_post() {
    netrc_config | curl -sS -K - "${tls_args[@]}" \
        -X POST -H 'Content-Type: application/json' --data "$2" \
        "$base_url$1"
}

# /api/health-diagnostic/status returns a bare object of category -> count,
# plus "total" and "totalFailed" which are not categories. Its keys are the
# authoritative list of categories: /api/health-diagnostic/report_ids is
# known to omit "hostsUsingSameName".
status=$(api_get /api/health-diagnostic/status)

categories=$(echo "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

while IFS= read -r category; do
    [ -n "$category" ] || continue
    report=$(api_post "/api/health-diagnostic/report/$category" '{"limit":10000}')
    # Report rows differ by category, but the first column is always
    # "key", the host's hostkey.
    echo "$report" | jq -r --arg category "$category" \
        '.data[0].rows[]? | [$category, .[0]] | @csv' \
        | sed 's/"//g'
done <<<"$categories"
