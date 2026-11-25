#!/usr/bin/env bash
# remove-host.sh HOSTNAME
#
# Completely removes the host with exactly HOSTNAME from CFEngine Mission Portal:
#   1. DELETE /api/host/:hostkey                     (moves it to deleted hosts)
#   2. DELETE /api/hosts/delete-permanently/:hostkey (removes the deleted-host record)
#   3. verifies the hostkey is in neither /api/host nor /api/hosts/deleted
#
# Environment: MP_URL, MP_USER, MP_PASSWORD (required)
#              MP_CACERT (optional: hub CA/cert file; without it TLS verification is skipped)
# Exit: 0 host verified gone; 1 usage error / no such host / ambiguous; 2 API or verification failure
set -euo pipefail

die() { echo "remove-host: $1" >&2; exit "${2:-2}"; }

[[ $# -eq 1 && -n $1 ]] || die "usage: remove-host.sh HOSTNAME" 1
target=$1
: "${MP_URL:?MP_URL not set}" "${MP_USER:?MP_USER not set}" "${MP_PASSWORD:?MP_PASSWORD not set}"
command -v jq >/dev/null || die "jq is required" 1
MP_URL=${MP_URL%/}

if [[ -n ${MP_CACERT:-} ]]; then tls=(--cacert "$MP_CACERT"); else tls=(-k); fi

# api METHOD PATH -> prints body; fails on non-2xx. Credentials go to curl on stdin.
api() {
    local method=$1 path=$2 out code
    out=$(printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
          curl -sS "${tls[@]}" -K - -X "$method" -w '\n%{http_code}' "$MP_URL$path") ||
        die "$method $path: transport error"
    code=${out##*$'\n'}
    out=${out%$'\n'*}
    [[ $code == 2* ]] || die "$method $path: HTTP $code: $out"
    printf '%s' "$out"
}

# All hosts from /api/host as one JSON array (paginated; default page size silently truncates).
all_hosts() {
    local page=1 acc='[]' body total
    while :; do
        body=$(api GET "/api/host?page=$page&count=500")
        acc=$(jq -c --argjson a "$acc" '$a + .data' <<<"$body")
        total=$(jq -r '.meta.total' <<<"$body")
        (( $(jq length <<<"$acc") >= total )) && break
        (( $(jq '.data|length' <<<"$body") > 0 )) || break
        page=$((page + 1))
    done
    printf '%s' "$acc"
}

deleted_hosts() { api GET /api/hosts/deleted | jq -c '.data'; }

in_list() { jq -e --arg k "$2" 'any(.[]; (.id // .hostkey) == $k)' <<<"$1" >/dev/null; }

# --- find exactly one host with exactly this hostname --------------------------------
hosts=$(all_hosts)
mapfile -t keys < <(jq -r --arg h "$target" '.[] | select(.hostname == $h) | .id' <<<"$hosts")

if (( ${#keys[@]} == 0 )); then
    die "no host has hostname exactly '$target'; nothing changed" 1
elif (( ${#keys[@]} > 1 )); then
    die "${#keys[@]} hosts have hostname '$target' (${keys[*]}); refusing to guess, nothing changed" 1
fi
key=${keys[0]}
echo "Found $target: $key"

# --- delete, then purge from deleted hosts --------------------------------------------
api DELETE "/api/host/$key" >/dev/null
echo "Deleted $key from the host list"

for _ in $(seq 1 30); do
    deleted=$(deleted_hosts)
    in_list "$deleted" "$key" && break
    sleep 2
done
in_list "$deleted" "$key" || die "$key did not appear in deleted hosts; cannot purge it"

api DELETE "/api/hosts/delete-permanently/$key" >/dev/null
echo "Permanently deleted $key from deleted hosts"

# --- verify ---------------------------------------------------------------------------
hosts=$(all_hosts)
deleted=$(deleted_hosts)
in_list "$hosts" "$key" && die "verification failed: $key still in host list"
jq -e --arg h "$target" 'any(.[]; .hostname == $h)' <<<"$hosts" >/dev/null &&
    die "verification failed: a host named '$target' is still in the host list"
in_list "$deleted" "$key" && die "verification failed: $key still among deleted hosts"

echo "Verified: $target ($key) is in neither the host list nor deleted hosts"
