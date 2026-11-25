#!/usr/bin/env bash
#
# remove-host.sh <hostname>
#
# Completely removes a host from CFEngine Mission Portal: it is first
# soft-deleted (DELETE /api/host/<id>), then purged from the "deleted
# hosts" bucket (DELETE /api/hosts/delete-permanently/<hostkey>), and
# finally the result is verified against both the active host list and
# the deleted-hosts list.
#
# Requires MP_URL, MP_USER, MP_PASSWORD in the environment. The hub
# certificate is self-signed, so curl is run with -k.

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <hostname>" >&2
    exit 1
fi

target_hostname=$1

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

# Populates HTTP_CODE and BODY, or exits 1 if the request itself fails
# (network/TLS error etc).
api_call() {
    local method=$1 path=$2
    local tmp
    tmp=$(mktemp)
    if ! HTTP_CODE=$(curl -k -s -o "$tmp" -w '%{http_code}' \
            -u "${MP_USER}:${MP_PASSWORD}" -X "$method" "${MP_URL}${path}"); then
        echo "Error: failed to reach Mission Portal at ${MP_URL}${path}" >&2
        rm -f "$tmp"
        exit 1
    fi
    BODY=$(<"$tmp")
    rm -f "$tmp"
}

api_call GET /api/host
if [[ "$HTTP_CODE" != "200" ]]; then
    echo "Error: could not list hosts (HTTP $HTTP_CODE): $BODY" >&2
    exit 1
fi

mapfile -t host_ids < <(jq -r --arg h "$target_hostname" \
    '.data[] | select(.hostname == $h) | .id' <<<"$BODY")

if [[ ${#host_ids[@]} -eq 0 ]]; then
    echo "Error: no host with hostname '$target_hostname' found in Mission Portal" >&2
    exit 1
fi

for id in "${host_ids[@]}"; do
    api_call DELETE "/api/host/$id"
    if [[ "$HTTP_CODE" != "202" && "$HTTP_CODE" != "200" ]]; then
        echo "Error: failed to delete host '$target_hostname' (id $id), HTTP $HTTP_CODE: $BODY" >&2
        exit 1
    fi
done

for id in "${host_ids[@]}"; do
    api_call DELETE "/api/hosts/delete-permanently/$id"
    if [[ "$HTTP_CODE" != "200" ]]; then
        echo "Error: failed to permanently delete host '$target_hostname' (id $id), HTTP $HTTP_CODE: $BODY" >&2
        exit 1
    fi
done

# Verify the host is gone from the active host list.
api_call GET /api/host
if [[ "$HTTP_CODE" != "200" ]]; then
    echo "Error: could not verify removal, host list request failed (HTTP $HTTP_CODE): $BODY" >&2
    exit 1
fi
if jq -e --arg h "$target_hostname" '.data[] | select(.hostname == $h)' <<<"$BODY" >/dev/null; then
    echo "Error: host '$target_hostname' still present in the host list after deletion" >&2
    exit 1
fi

# Verify the host is gone from the deleted-hosts list.
api_call GET /api/hosts/deleted
if [[ "$HTTP_CODE" != "200" ]]; then
    echo "Error: could not verify removal, deleted-hosts list request failed (HTTP $HTTP_CODE): $BODY" >&2
    exit 1
fi
for id in "${host_ids[@]}"; do
    if jq -e --arg id "$id" '.data[] | select(.hostkey == $id)' <<<"$BODY" >/dev/null; then
        echo "Error: host '$target_hostname' (id $id) still present among deleted hosts" >&2
        exit 1
    fi
done

echo "Host '$target_hostname' has been completely removed from Mission Portal (verified absent from host list and deleted hosts)."
exit 0
