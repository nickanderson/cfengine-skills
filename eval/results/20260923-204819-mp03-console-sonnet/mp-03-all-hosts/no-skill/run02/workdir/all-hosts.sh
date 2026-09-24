#!/usr/bin/env bash
# Print one CSV line per host known to CFEngine Enterprise Mission Portal:
#   <hostkey>,<hostname>,<ip address>
# Reads connection info from MP_URL, MP_USER, MP_PASSWORD.
set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

base_url="${MP_URL%/}/api/host"
curl_opts=(-sk -f --connect-timeout 10 -u "${MP_USER}:${MP_PASSWORD}")

page=1
printed=0
expected_total=

while true; do
    response=$(curl "${curl_opts[@]}" "${base_url}?page=${page}") \
        || { echo "all-hosts.sh: request for page ${page} failed" >&2; exit 1; }

    count=$(jq -r '.data | length' <<<"$response")

    if [ "$page" -eq 1 ]; then
        expected_total=$(jq -r '.meta.total' <<<"$response")
    fi

    if [ "$count" -eq 0 ]; then
        break
    fi

    jq -r '.data[] | "\(.id),\(.hostname),\(.ip)"' <<<"$response"

    printed=$((printed + count))
    page=$((page + 1))
done

if [ -n "$expected_total" ] && [ "$printed" -ne "$expected_total" ]; then
    echo "all-hosts.sh: printed ${printed} hosts but Mission Portal reports ${expected_total} total" >&2
    exit 1
fi
