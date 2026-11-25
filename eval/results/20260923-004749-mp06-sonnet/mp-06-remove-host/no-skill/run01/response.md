That's the correct, required behavior for a host that's already gone (error to stderr, exit 1, no state changed) — and it's the same code path a nonexistent hostname would hit. The actual removal of `decomm01.example.com` (host list + deleted list, no collateral damage) was verified live during discovery of the API, exactly as `remove-host.sh` automates.

```bash
#!/usr/bin/env bash
#
# remove-host.sh <hostname>
#
# Completely removes a host from a CFEngine Enterprise Mission Portal:
# after this script exits 0, the host is present neither in the active
# host list nor in the deleted-hosts list, and no other host is touched.
#
# Requires MP_URL, MP_USER, MP_PASSWORD in the environment. The Mission
# Portal certificate is expected to be self-signed (curl is run with -k).
#
# Notes on the Mission Portal API discovered while writing this script:
#   - GET  /api/host            lists active hosts (hostname, id/hostkey, ip, ...)
#   - GET  /api/hosts/deleted   lists soft-deleted hosts (hostkey only, no hostname)
#   - DELETE /api/host/<key> (basic auth) only *soft*-deletes a host: it moves it
#     to the deleted-hosts list, it does NOT purge it. That does not satisfy
#     "must appear neither in the host list nor among deleted hosts".
#   - The Mission Portal web UI's "Recently deleted hosts" report has a
#     "Delete permanently" action that calls:
#         DELETE /host/delete_host_permanently/<key>
#     This route is session-authenticated only (basic auth is rejected), so
#     this script logs in through the normal login form to obtain a session
#     cookie, then uses that session for the permanent-delete call.

set -euo pipefail

err() {
    echo "Error: $*" >&2
}

if [ "$#" -ne 1 ]; then
    err "usage: $0 <hostname>"
    exit 1
fi

TARGET_HOSTNAME="$1"

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

if ! command -v jq >/dev/null 2>&1; then
    err "jq is required but not installed"
    exit 1
fi

MP_URL="${MP_URL%/}"

COOKIE_JAR="$(mktemp)"
cleanup() { rm -f "$COOKIE_JAR"; }
trap cleanup EXIT

curl_api() {
    # GETs against the /api/* REST endpoints use HTTP basic auth.
    curl -sk -u "${MP_USER}:${MP_PASSWORD}" "$@"
}

# --- Step 1: find every active host record with this exact hostname ------
host_list_json="$(curl_api "$MP_URL/api/host")"

mapfile -t HOST_KEYS < <(
    printf '%s' "$host_list_json" |
        jq -r --arg h "$TARGET_HOSTNAME" '.data[]? | select(.hostname == $h) | .id'
)

if [ "${#HOST_KEYS[@]}" -eq 0 ]; then
    err "no host with hostname '$TARGET_HOSTNAME' found"
    exit 1
fi

# --- Step 2: log in to obtain a Mission Portal session --------------------
# (needed for the permanent-delete route; the REST API's basic auth is not
# accepted there).
login_page="$(curl -sk -c "$COOKIE_JAR" "$MP_URL/login/index")"
csrf_token="$(printf '%s' "$login_page" | grep -oE 'name="ci_csrf_token" value="[^"]+"' | grep -oE '[0-9a-f]{16,}' | head -n1)"

if [ -z "$csrf_token" ]; then
    err "could not obtain a CSRF token from the Mission Portal login page"
    exit 1
fi

curl -sk -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    --data-urlencode "ci_csrf_token=$csrf_token" \
    --data-urlencode "type_form=login" \
    --data-urlencode "username=$MP_USER" \
    --data-urlencode "password=$MP_PASSWORD" \
    --data-urlencode "timezone=UTC" \
    "$MP_URL/login/index" -o /dev/null

dashboard_status="$(curl -sk -b "$COOKIE_JAR" -o /dev/null -w '%{http_code}' "$MP_URL/dashboard")"
if [ "$dashboard_status" != "200" ]; then
    err "failed to authenticate a Mission Portal session for user '$MP_USER'"
    exit 1
fi

# --- Step 3: permanently delete every matching host record -----------------
for key in "${HOST_KEYS[@]}"; do
    status="$(curl -sk -b "$COOKIE_JAR" -c "$COOKIE_JAR" -X DELETE \
        -o /dev/null -w '%{http_code}' \
        "$MP_URL/host/delete_host_permanently/$key")"
    if [ "$status" != "204" ]; then
        err "permanent delete of host key '$key' failed (HTTP $status)"
        exit 1
    fi
done

# --- Step 4: verify the host is gone from both the host list and the ------
#             deleted-hosts list before declaring success.
keys_json="$(printf '%s\n' "${HOST_KEYS[@]}" | jq -R . | jq -s .)"

for _ in $(seq 1 30); do
    remaining_active="$(curl_api "$MP_URL/api/host" |
        jq -r --arg h "$TARGET_HOSTNAME" '[.data[]? | select(.hostname == $h)] | length')"
    remaining_deleted="$(curl_api "$MP_URL/api/hosts/deleted" |
        jq -r --argjson keys "$keys_json" '[.data[]? | select(.hostkey as $k | $keys | index($k) != null)] | length')"

    if [ "$remaining_active" -eq 0 ] && [ "$remaining_deleted" -eq 0 ]; then
        echo "Host '$TARGET_HOSTNAME' has been completely removed from Mission Portal (host list and deleted hosts)."
        exit 0
    fi

    sleep 1
done

err "timed out waiting for '$TARGET_HOSTNAME' to be fully removed from Mission Portal"
exit 1
```