#!/usr/bin/env bash
#
# remove-host.sh - completely remove a host from CFEngine Mission Portal
#
# Usage: remove-host.sh <hostname>
#
# Requires MP_URL, MP_USER, MP_PASSWORD in the environment.
# The Mission Portal certificate is self-signed, so curl is run with -k.

set -u -o pipefail

HOSTNAME_ARG="${1:-}"

if [[ -z "$HOSTNAME_ARG" ]]; then
    echo "Usage: $0 <hostname>" >&2
    exit 1
fi

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

CURL=(curl -sk -u "${MP_USER}:${MP_PASSWORD}")

# Poll settings for waiting on the asynchronous cf-hub deletion job.
POLL_INTERVAL=15
POLL_TIMEOUT=900   # 15 minutes; cf-hub picks up deletion jobs on its own schedule

api_get() {
    "${CURL[@]}" "${MP_URL}$1"
}

url_encode() {
    python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

# Find every host entry whose hostname is an EXACT match for the argument.
# (Mission Portal can hold multiple entries with the same hostname under
# different host keys, and unrelated hosts can have similar-looking names,
# e.g. "lab-decomm01.example.com" vs "decomm01.example.com" -- only exact
# matches on the hostname field are removed.)
list_json=$(api_get "/api/host")
if [[ -z "$list_json" ]]; then
    echo "Error: failed to reach Mission Portal at ${MP_URL}" >&2
    exit 1
fi

mapfile -t host_keys < <(printf '%s' "$list_json" | python3 -c '
import json, sys
target = sys.argv[1]
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(1)
for h in data.get("data", []):
    if h.get("hostname") == target:
        print(h["id"])
' "$HOSTNAME_ARG")

if [[ ${#host_keys[@]} -eq 0 ]]; then
    echo "Error: no host with hostname '${HOSTNAME_ARG}' found in Mission Portal" >&2
    exit 1
fi

echo "Found ${#host_keys[@]} host entry(ies) for '${HOSTNAME_ARG}':"
for key in "${host_keys[@]}"; do
    echo "  ${key}"
done

# Schedule deletion of every matching host key.
for key in "${host_keys[@]}"; do
    enc_key=$(url_encode "$key")
    status=$("${CURL[@]}" -o /tmp/remove-host-delete-body.$$ -w '%{http_code}' -X DELETE "${MP_URL}/api/host/${enc_key}")
    body=$(cat /tmp/remove-host-delete-body.$$ 2>/dev/null)
    rm -f /tmp/remove-host-delete-body.$$

    if [[ "$status" != "202" && "$status" != "200" ]]; then
        echo "Error: failed to delete host key ${key} (HTTP ${status}): ${body}" >&2
        exit 1
    fi
    echo "Deletion scheduled for host key ${key} (HTTP ${status})"
done

echo "Waiting for Mission Portal to complete removal (this can take several minutes)..."

elapsed=0
while (( elapsed < POLL_TIMEOUT )); do
    still_in_list=$(api_get "/api/host" | python3 -c '
import json, sys
target = sys.argv[1]
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    print("unknown")
    sys.exit(0)
print("yes" if any(h.get("hostname") == target for h in data.get("data", [])) else "no")
' "$HOSTNAME_ARG")

    still_in_deleted="no"
    deleted_json=$(api_get "/api/hosts/deleted")
    for key in "${host_keys[@]}"; do
        match=$(printf '%s' "$deleted_json" | python3 -c '
import json, sys
target = sys.argv[1]
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    print("no")
    sys.exit(0)
print("yes" if any(h.get("hostkey") == target for h in data.get("data", [])) else "no")
' "$key")
        if [[ "$match" == "yes" ]]; then
            still_in_deleted="yes"
            break
        fi
    done

    if [[ "$still_in_list" == "no" && "$still_in_deleted" == "no" ]]; then
        echo "Verified: '${HOSTNAME_ARG}' no longer appears in the host list or the deleted hosts list."
        exit 0
    fi

    sleep "$POLL_INTERVAL"
    elapsed=$(( elapsed + POLL_INTERVAL ))
done

echo "Error: timed out after ${POLL_TIMEOUT}s waiting for '${HOSTNAME_ARG}' to be fully removed from Mission Portal" >&2
exit 1
