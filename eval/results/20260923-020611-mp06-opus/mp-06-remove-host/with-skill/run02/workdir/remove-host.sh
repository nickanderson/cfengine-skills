#!/usr/bin/env bash
# remove-host.sh HOSTNAME
#
# Completely remove one host from CFEngine Enterprise Mission Portal:
#   1. DELETE /api/host/:hostkey                  (host -> "deleted hosts")
#   2. DELETE /api/hosts/delete-permanently/:key  (purge the deleted-host record)
#   3. verify it is in neither list and that no other host changed.
#
# Environment: MP_URL, MP_USER, MP_PASSWORD (required)
#              MP_CACERT (optional; hub certificate file. Without it TLS
#                         verification is skipped, since the hub is self-signed)
#
# Exit: 0 host verified gone; 1 no host with exactly that hostname (nothing
# changed); 2 usage/config/API error or verification failure; 3 hostname is
# ambiguous (several hosts share it; nothing changed).
set -euo pipefail

die() { echo "remove-host: $1" >&2; exit "${2:-2}"; }

[ $# -eq 1 ] && [ -n "$1" ] || die "usage: remove-host.sh HOSTNAME"
TARGET=$1
[ -n "${MP_URL:-}" ] && [ -n "${MP_USER:-}" ] && [ -n "${MP_PASSWORD:-}" ] \
    || die "MP_URL, MP_USER and MP_PASSWORD must be set"
command -v jq >/dev/null || die "jq is required"
MP_URL=${MP_URL%/}

if [ -n "${MP_CACERT:-}" ]; then TLS=(--cacert "$MP_CACERT"); else TLS=(-k); fi
HUB_HOST=$(printf '%s' "$MP_URL" | sed -E 's#^[a-zA-Z]+://##; s#[:/].*$##')

BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT

# api METHOD PATH -> sets $STATUS (HTTP code) and $BODY.
# Credentials go to curl as a netrc on a pipe, never on the command line.
api() {
    STATUS=$(curl -sS "${TLS[@]}" -X "$1" \
        --netrc-file <(printf 'machine %s login %s password %s\n' "$HUB_HOST" "$MP_USER" "$MP_PASSWORD") \
        -o "$BODY_FILE" -w '%{http_code}' "$MP_URL$2") || die "transport error calling $1 $2"
    BODY=$(<"$BODY_FILE")
}

# HOSTS := all hosts as sorted "hostkey<TAB>hostname" lines, paging to meta.total.
list_hosts() {
    local page=1 got=0 total n acc=""
    while :; do
        api GET "/api/host?page=$page&count=100"
        [ "$STATUS" = 200 ] || die "GET /api/host failed: HTTP $STATUS: $BODY"
        acc+=$(jq -r '.data[] | [.id, .hostname] | @tsv' <<<"$BODY")$'\n'
        total=$(jq -r '.meta.total' <<<"$BODY")
        n=$(jq '.data | length' <<<"$BODY")
        got=$((got + n))
        if [ "$got" -ge "$total" ] || [ "$n" -eq 0 ]; then break; fi
        page=$((page + 1))
    done
    HOSTS=$(grep . <<<"$acc" | sort || true)
}

# DELETED := sorted hostkeys of all deleted hosts.
list_deleted() {
    api GET "/api/hosts/deleted"
    [ "$STATUS" = 200 ] || die "GET /api/hosts/deleted failed: HTTP $STATUS: $BODY"
    DELETED=$(jq -r '.data[].hostkey' <<<"$BODY" | sort)
}

count() { grep -c . <<<"$1" || true; }

list_hosts;   hosts_before=$HOSTS
list_deleted; deleted_before=$DELETED

# Exact, case-sensitive hostname match (no substrings, no regex).
matches=$(awk -F'\t' -v h="$TARGET" '$2 == h { print $1 }' <<<"$hosts_before")
n=$(count "$matches")

if [ "$n" -eq 0 ]; then
    die "no host with hostname exactly '$TARGET' in Mission Portal; nothing changed" 1
elif [ "$n" -gt 1 ]; then
    { echo "remove-host: hostname '$TARGET' is shared by $n hosts; refusing to guess. Nothing changed."
      sed 's/^/  /' <<<"$matches"; } >&2
    exit 3
fi
KEY=$matches
echo "Found $TARGET: $KEY"

# 1. Delete the host (moves it to the deleted-hosts list).
api DELETE "/api/host/$KEY"
case "$STATUS" in 2??) ;; *) die "DELETE /api/host/$KEY failed: HTTP $STATUS: $BODY";; esac
echo "Deleted host $KEY (HTTP $STATUS)"

# 2. Wait for it to appear among deleted hosts (required before purging), then purge.
for _ in $(seq 1 30); do
    list_deleted
    grep -qxF "$KEY" <<<"$DELETED" && break
    sleep 2
done
grep -qxF "$KEY" <<<"$DELETED" || die "$KEY did not appear in /api/hosts/deleted; cannot purge it"

api DELETE "/api/hosts/delete-permanently/$KEY"
case "$STATUS" in 2??) ;; *) die "DELETE /api/hosts/delete-permanently/$KEY failed: HTTP $STATUS: $BODY";; esac
echo "Permanently deleted $KEY (HTTP $STATUS)"

# 3. Verify: gone from both lists, and nothing else changed.
list_hosts;   hosts_after=$HOSTS
list_deleted; deleted_after=$DELETED

fail=0
if awk -F'\t' -v k="$KEY" -v h="$TARGET" '$1 == k || $2 == h' <<<"$hosts_after" | grep -q .; then
    echo "remove-host: VERIFY FAILED: $TARGET/$KEY is still in the host list" >&2; fail=1
fi
if grep -qxF "$KEY" <<<"$deleted_after"; then
    echo "remove-host: VERIFY FAILED: $KEY is still among deleted hosts" >&2; fail=1
fi
api GET "/api/host/$KEY"
if [ "$STATUS" != 404 ]; then
    echo "remove-host: VERIFY FAILED: GET /api/host/$KEY returned HTTP $STATUS, expected 404" >&2; fail=1
fi
expected_hosts=$(awk -F'\t' -v k="$KEY" '$1 != k' <<<"$hosts_before")
if [ "$hosts_after" != "$expected_hosts" ]; then
    echo "remove-host: VERIFY FAILED: other hosts changed (expected vs actual):" >&2
    diff <(echo "$expected_hosts") <(echo "$hosts_after") >&2 || true; fail=1
fi
if [ "$deleted_after" != "$deleted_before" ]; then
    echo "remove-host: VERIFY FAILED: deleted-hosts list changed (before vs after):" >&2
    diff <(echo "$deleted_before") <(echo "$deleted_after") >&2 || true; fail=1
fi
[ "$fail" -eq 0 ] || exit 2

echo "Verified: $TARGET ($KEY) is in neither the host list nor deleted hosts;" \
     "the other $(count "$hosts_after") host(s) and $(count "$deleted_after") deleted host(s) are unchanged."
