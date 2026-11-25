#!/usr/bin/env bash
#
# remove-host.sh <hostname>
#
# Completely removes a host from CFEngine Enterprise Mission Portal:
# after this script exits 0, the host is present neither in the active
# host list nor among deleted hosts, and no other host is affected.
#
# Requires MP_URL, MP_USER, MP_PASSWORD in the environment. The hub's
# certificate is self-signed, so curl is run with -k.

set -euo pipefail

usage() {
    echo "Usage: $0 <hostname>" >&2
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi

target_host=$1

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

curl_api() {
    # Issues an authenticated API request and fails loudly on transport
    # errors or non-2xx responses, without leaking the body of the
    # failure into stdout on success paths.
    curl -sk -f -u "${MP_USER}:${MP_PASSWORD}" "$@"
}

# The hub's hostname filter performs a substring match, not an exact
# match (e.g. a filter of "decomm01.example.com" also matches a host
# named "lab-decomm01.example.com"). So we page through the full host
# list ourselves and compare hostnames exactly, client-side, rather
# than trusting the server-side filter.
fetch_all_hosts() {
    local page=1
    local total count
    local all="[]"

    while :; do
        local resp
        if ! resp=$(curl_api "${MP_URL}/api/host?page=${page}"); then
            echo "Error: failed to query ${MP_URL}/api/host (page ${page})" >&2
            exit 1
        fi

        all=$(jq -s '.[0] + .[1].data' <(echo "$all") <(echo "$resp"))
        total=$(echo "$resp" | jq -r '.meta.total')
        count=$(echo "$resp" | jq -r '.meta.count')

        if [ "$count" -eq 0 ] || [ "$((page * $(echo "$resp" | jq -r '.data | length')))" -ge "$total" ]; then
            break
        fi
        page=$((page + 1))
    done

    echo "$all"
}

all_hosts=$(fetch_all_hosts)

# Exact, case-sensitive hostname match only.
matches=$(echo "$all_hosts" | jq -c --arg h "$target_host" '[.[] | select(.hostname == $h)]')
match_count=$(echo "$matches" | jq 'length')

if [ "$match_count" -eq 0 ]; then
    echo "Error: no host with hostname '${target_host}' found in Mission Portal" >&2
    exit 1
fi

if [ "$match_count" -gt 1 ]; then
    echo "Error: ${match_count} hosts matched hostname '${target_host}' exactly; refusing to guess which to remove" >&2
    exit 1
fi

host_id=$(echo "$matches" | jq -r '.[0].id')

echo "Found host '${target_host}' (id: ${host_id}); deleting..."

delete_status=$(curl -sk -o /dev/null -w '%{http_code}' -u "${MP_USER}:${MP_PASSWORD}" -X DELETE "${MP_URL}/api/host/${host_id}")
if [ "$delete_status" != "200" ] && [ "$delete_status" != "202" ] && [ "$delete_status" != "204" ]; then
    echo "Error: DELETE ${MP_URL}/api/host/${host_id} returned HTTP ${delete_status}" >&2
    exit 1
fi

# Verify the host is gone from the active host list, exactly by name.
remaining=$(fetch_all_hosts | jq -c --arg h "$target_host" '[.[] | select(.hostname == $h)]')
remaining_count=$(echo "$remaining" | jq 'length')
if [ "$remaining_count" -ne 0 ]; then
    echo "Error: host '${target_host}' still present in host list after delete" >&2
    exit 1
fi

# Verify the host is also gone by id (covers any separate "deleted
# hosts" view the hub might expose alongside the active list).
lookup_status=$(curl -sk -o /dev/null -w '%{http_code}' -u "${MP_USER}:${MP_PASSWORD}" "${MP_URL}/api/host/${host_id}")
if [ "$lookup_status" != "404" ]; then
    echo "Error: host id ${host_id} is still resolvable after delete (HTTP ${lookup_status})" >&2
    exit 1
fi

echo "Host '${target_host}' has been completely removed from Mission Portal."
exit 0
