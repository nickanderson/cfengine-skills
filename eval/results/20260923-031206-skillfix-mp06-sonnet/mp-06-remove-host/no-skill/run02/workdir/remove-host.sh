#!/usr/bin/env bash
#
# remove-host.sh <hostname>
#
# Removes a host from CFEngine Enterprise Mission Portal completely: the
# host is deleted via the Mission Portal REST API and the script verifies
# that it is gone from both the active host list and the deleted-hosts
# list before exiting successfully.
#
# Requires MP_URL, MP_USER, MP_PASSWORD to be set in the environment.
# The hub certificate is expected to be self-signed (curl -k is used).

set -euo pipefail

usage() {
    echo "Usage: $0 <hostname>" >&2
}

if [ "$#" -ne 1 ]; then
    usage
    exit 1
fi

TARGET_HOSTNAME="$1"

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

for bin in curl jq; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "Error: required tool '${bin}' not found in PATH" >&2
        exit 1
    fi
done

CURL_AUTH=(-sk -u "${MP_USER}:${MP_PASSWORD}")

# GET a JSON API path, aborting with a clear error if the hub does not
# answer with a successful HTTP status.
api_get() {
    local path="$1" body status
    body="$(curl "${CURL_AUTH[@]}" -w $'\n%{http_code}' "${MP_URL}${path}")"
    status="${body##*$'\n'}"
    body="${body%$'\n'*}"
    if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
        echo "Error: GET ${path} failed with HTTP status ${status}: ${body}" >&2
        exit 1
    fi
    printf '%s' "$body"
}

# Count exact (non-substring, case-sensitive) hostname matches in the
# active host list.
count_active_matches() {
    api_get "/api/host" | jq -r --arg h "$TARGET_HOSTNAME" \
        '[.data[] | select(.hostname == $h)] | length'
}

# Count exact hostname matches in the deleted-hosts list. That endpoint
# only ever reports hostkey/IP, never hostname, so this is a defensive
# check in case that ever changes -- it is expected to always be 0.
count_deleted_matches() {
    api_get "/api/hosts/deleted" | jq -r --arg h "$TARGET_HOSTNAME" \
        '[.data[] | select(.hostname? == $h)] | length'
}

HOST_LIST_JSON="$(api_get "/api/host")"

MATCH_COUNT="$(jq -r --arg h "$TARGET_HOSTNAME" \
    '[.data[] | select(.hostname == $h)] | length' <<<"$HOST_LIST_JSON")"

if [ "$MATCH_COUNT" -eq 0 ]; then
    echo "Error: no host with hostname '${TARGET_HOSTNAME}' found in Mission Portal" >&2
    exit 1
fi

if [ "$MATCH_COUNT" -gt 1 ]; then
    echo "Error: ${MATCH_COUNT} hosts match hostname '${TARGET_HOSTNAME}'; refusing to guess which one to delete" >&2
    exit 1
fi

HOST_ID="$(jq -r --arg h "$TARGET_HOSTNAME" \
    '.data[] | select(.hostname == $h) | .id' <<<"$HOST_LIST_JSON")"

echo "Found host '${TARGET_HOSTNAME}' (id ${HOST_ID}); deleting..." >&2

DELETE_STATUS="$(curl "${CURL_AUTH[@]}" -o /dev/null -w '%{http_code}' \
    -X DELETE "${MP_URL}/api/host/${HOST_ID}")"

if [ "$DELETE_STATUS" -lt 200 ] || [ "$DELETE_STATUS" -ge 300 ]; then
    echo "Error: DELETE /api/host/${HOST_ID} failed with HTTP status ${DELETE_STATUS}" >&2
    exit 1
fi

# Deletion is processed asynchronously by the hub, so poll briefly until
# the host is confirmed gone from both the active and deleted host lists.
TIMEOUT=60
INTERVAL=2
ELAPSED=0
while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    if [ "$(count_active_matches)" -eq 0 ] && [ "$(count_deleted_matches)" -eq 0 ]; then
        echo "Host '${TARGET_HOSTNAME}' has been completely removed from Mission Portal."
        exit 0
    fi
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "Error: timed out waiting for host '${TARGET_HOSTNAME}' to be fully removed from Mission Portal" >&2
exit 1
