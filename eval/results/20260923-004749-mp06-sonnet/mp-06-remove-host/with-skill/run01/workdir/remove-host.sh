#!/usr/bin/env bash
#
# remove-host.sh HOSTNAME
#
# Completely removes a host from CFEngine Enterprise Mission Portal: after
# a successful run the host appears neither in the active host list nor
# among deleted hosts. No other host is touched.
#
# Requires environment variables:
#   MP_URL       Base URL of the hub, e.g. https://192.168.56.2
#   MP_USER      Mission Portal username
#   MP_PASSWORD  Mission Portal password
# Optional:
#   MP_CACERT    Path to a CA certificate to verify the hub's TLS cert.
#                If unset, certificate verification is skipped (-k), since
#                the hub is documented to use a self-signed certificate.
#
# Exit codes:
#   0  host confirmed completely removed
#   1  no host with exactly this hostname exists (nothing changed)
#   2  usage / configuration error
#   3  API error while deleting
#   4  deletion issued but could not be verified complete in time

set -u -o pipefail

die_usage() {
    echo "Usage: $0 HOSTNAME" >&2
    exit 2
}

[ $# -eq 1 ] || die_usage
hostname=$1

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

for bin in curl jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "$0: '$bin' is required but not found" >&2; exit 2; }
done

# Host part only (no scheme/port) for the netrc "machine" match.
mp_host=${MP_URL#*://}
mp_host=${mp_host%%/*}
mp_host=${mp_host%%:*}

cacert_args=()
if [ -n "${MP_CACERT:-}" ]; then
    cacert_args=(--cacert "$MP_CACERT")
else
    echo "$0: MP_CACERT not set, skipping TLS certificate verification" >&2
    cacert_args=(-k)
fi

netrc() {
    printf 'machine %s login %s password %s\n' "$mp_host" "$MP_USER" "$MP_PASSWORD"
}

# api METHOD PATH -> prints body to stdout, sets $status
body=""
status=""
api() {
    local method=$1 path=$2 resp
    resp=$(curl -sS -w '\n%{http_code}' \
        --netrc-file <(netrc) \
        "${cacert_args[@]}" \
        -X "$method" \
        "$MP_URL$path") || { echo "$0: request to $path failed (network/TLS error)" >&2; exit 3; }
    status=${resp##*$'\n'}
    body=${resp%$'\n'*}
}

# List every host whose hostname is an EXACT match, paging through /api/host.
find_matching_hostkeys() {
    local page=1 count=200 total got
    local keys=()
    while :; do
        api GET "/api/host?page=${page}&count=${count}"
        if [ "$status" != "200" ]; then
            echo "$0: GET /api/host failed (HTTP $status): $body" >&2
            exit 3
        fi
        total=$(jq -r '.meta.total // 0' <<<"$body")
        got=$(jq -r '.data | length' <<<"$body")
        while IFS= read -r key; do
            [ -n "$key" ] && keys+=("$key")
        done < <(jq -r --arg h "$hostname" '.data[] | select(.hostname == $h) | .id' <<<"$body")
        (( got == 0 )) && break
        (( page * count >= total )) && break
        page=$((page + 1))
    done
    if [ "${#keys[@]}" -gt 0 ]; then
        printf '%s\n' "${keys[@]}"
    fi
}

# True (0) if $1 (hostkey) is currently listed in /api/hosts/deleted.
in_deleted_list() {
    local target=$1
    api GET "/api/hosts/deleted"
    if [ "$status" != "200" ]; then
        echo "$0: GET /api/hosts/deleted failed (HTTP $status): $body" >&2
        exit 3
    fi
    jq -e --arg k "$target" '.data | any(.hostkey == $k)' <<<"$body" >/dev/null
}

# True (0) if hostname still appears anywhere in the active host list.
hostname_in_host_list() {
    local page=1 count=200 total got found=1
    while :; do
        api GET "/api/host?page=${page}&count=${count}"
        [ "$status" = "200" ] || { echo "$0: GET /api/host failed (HTTP $status): $body" >&2; exit 3; }
        total=$(jq -r '.meta.total // 0' <<<"$body")
        got=$(jq -r '.data | length' <<<"$body")
        if jq -e --arg h "$hostname" '.data[] | select(.hostname == $h)' <<<"$body" >/dev/null; then
            found=0
            break
        fi
        (( got == 0 )) && break
        (( page * count >= total )) && break
        page=$((page + 1))
    done
    return $found
}

mapfile -t hostkeys < <(find_matching_hostkeys)

if [ "${#hostkeys[@]}" -eq 0 ]; then
    echo "$0: no host with hostname '$hostname' exists in Mission Portal" >&2
    exit 1
fi

echo "Found ${#hostkeys[@]} host(s) matching '$hostname':"
printf '  %s\n' "${hostkeys[@]}"

for key in "${hostkeys[@]}"; do
    echo "Removing $key ..."
    api DELETE "/api/host/${key}"
    if [ "$status" != "202" ] && [ "$status" != "200" ]; then
        echo "$0: DELETE /api/host/$key failed (HTTP $status): $body" >&2
        exit 3
    fi
done

# Wait for each host to show up as deleted, then purge it permanently.
for key in "${hostkeys[@]}"; do
    attempt=0
    until in_deleted_list "$key"; do
        attempt=$((attempt + 1))
        if [ "$attempt" -ge 20 ]; then
            echo "$0: $key never appeared in the deleted hosts list; cannot permanently purge it" >&2
            exit 4
        fi
        sleep 3
    done

    echo "Purging $key permanently ..."
    api DELETE "/api/hosts/delete-permanently/${key}"
    if [ "$status" != "200" ]; then
        echo "$0: DELETE /api/hosts/delete-permanently/$key failed (HTTP $status): $body" >&2
        exit 3
    fi
done

# Final verification: hostname gone from the host list, hostkeys gone from
# the deleted list. Retry briefly in case the hub needs a moment to settle.
attempt=0
while :; do
    still_active=0
    hostname_in_host_list && still_active=1

    still_deleted=0
    for key in "${hostkeys[@]}"; do
        if in_deleted_list "$key"; then
            still_deleted=1
            break
        fi
    done

    if [ "$still_active" -eq 0 ] && [ "$still_deleted" -eq 0 ]; then
        echo "Verified: '$hostname' no longer appears in the host list or the deleted hosts list."
        exit 0
    fi

    attempt=$((attempt + 1))
    if [ "$attempt" -ge 20 ]; then
        echo "$0: could not verify complete removal of '$hostname' within the timeout" >&2
        exit 4
    fi
    sleep 3
done
