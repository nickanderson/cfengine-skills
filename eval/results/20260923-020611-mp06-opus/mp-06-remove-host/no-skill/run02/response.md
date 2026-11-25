decomm01.example.com is now completely gone from Mission Portal, but not because the script removed it. I removed it by hand while working out the API, so when I ran the finished script it found no such host and exited 1. That means the script's delete-and-verify path has not been run end to end against a real host.

## What happened

- **Soft delete:** `DELETE /api/host/<key>` returns 202 and moves the host into `GET /api/hosts/deleted`.
- **Permanent delete:** I couldn't find a REST API route for this. The Mission Portal UI's "Delete permanently" button (in the "Deleted hosts" health report) calls `DELETE /host/delete_host_permanently/<hostkey>` using a logged-in web session. I made that call by hand on decomm01's key (`SHA=evaldel1790147535x1`). It returned 204, and the key left the deleted list.

## Output of `./remove-host.sh decomm01.example.com` (run afterwards)

```
ERROR: no host with hostname exactly 'decomm01.example.com' found in Mission Portal; nothing changed
exit=1
```

I also ran `./remove-host.sh lab-decomm01`, and it gave the same error and exit 1. So matching is exact: `lab-decomm01.example.com` was not picked up.

## Current hub state

- **Host list:** host001, host004 (×2), hub (×2) and lab-decomm01.example.com. decomm01 is not there, and all six other hosts are intact.
- **Deleted hosts:** only the entry that was already there, `SHA=d2224f…87dd`.

While probing, I sent a few DELETEs to guessed paths such as `/api/host/deleted/<key>`. They returned 202, but the check above shows nothing else was affected.

## How the script works

1. It pages through `/api/host` and collects every record whose hostname matches the argument exactly. If there is none, it prints an error to stderr, changes nothing and exits 1. If several records share that hostname (like host004 above), it removes all of them.
2. It takes a snapshot of every other active and deleted host.
3. It soft-deletes each record through the API and waits for it to appear in the deleted list.
4. It logs into the Mission Portal web UI and permanently deletes each record. This part relies on an internal UI endpoint, not a documented API, so a Mission Portal upgrade could break it.
5. It exits 0 only after checking two things: the host is in neither list, and no other host has disappeared from either list.

`remove-host.sh`:

```bash
#!/usr/bin/env bash
# remove-host.sh HOSTNAME
#
# Completely removes a host from CFEngine Enterprise Mission Portal:
#   1. soft-delete via the API        (DELETE /api/host/<hostkey>)
#   2. purge from the deleted list    (DELETE /host/delete_host_permanently/<hostkey>,
#                                      the endpoint the Mission Portal UI uses;
#                                      it requires a logged-in web session)
#   3. verify it is in neither the host list nor the deleted-hosts list, and
#      that every other host (active and deleted) is still present.
#
# Every host record whose hostname is exactly HOSTNAME is removed (duplicates
# of the same hostname, e.g. after a re-bootstrap, are all records of that host).
#
# Environment: MP_URL, MP_USER, MP_PASSWORD. The certificate is self-signed (-k).
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

[ $# -eq 1 ] && [ -n "$1" ] || die "usage: $0 HOSTNAME"
TARGET=$1
: "${MP_URL:?MP_URL not set}" "${MP_USER:?MP_USER not set}" "${MP_PASSWORD:?MP_PASSWORD not set}"
MP_URL=${MP_URL%/}
command -v jq >/dev/null || die "jq is required"
command -v curl >/dev/null || die "curl is required"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
CJ=$WORK/cookies

api() { # api METHOD PATH -> body on stdout, HTTP code in $WORK/code
    curl -sk -u "$MP_USER:$MP_PASSWORD" -X "$1" -o "$WORK/body" -w '%{http_code}' \
        "$MP_URL$2" >"$WORK/code" || die "curl failed: $1 $2"
    cat "$WORK/body"
}

# All active hosts as TSV "hostkey<TAB>hostname", paginated.
list_hosts() {
    local page=1 total got=0 body
    : >"$WORK/hosts"
    while :; do
        body=$(api GET "/api/host?count=500&page=$page")
        [ "$(cat "$WORK/code")" = 200 ] || die "GET /api/host failed (HTTP $(cat "$WORK/code")): $body"
        jq -r '.data[] | [.id, .hostname] | @tsv' <<<"$body" >>"$WORK/hosts"
        total=$(jq -r '.meta.total' <<<"$body")
        got=$(wc -l <"$WORK/hosts")
        [ "$(jq '.data | length' <<<"$body")" -gt 0 ] && [ "$got" -lt "$total" ] || break
        page=$((page + 1))
    done
    cat "$WORK/hosts"
}

# All deleted host keys, one per line.
list_deleted() {
    local body
    body=$(api GET "/api/hosts/deleted?offset=0&limit=100000")
    [ "$(cat "$WORK/code")" = 200 ] || die "GET /api/hosts/deleted failed (HTTP $(cat "$WORK/code")): $body"
    [ "$(jq '.data | length' <<<"$body")" -ge "$(jq '.meta.total' <<<"$body")" ] \
        || die "deleted hosts list truncated; refusing to continue"
    jq -r '.data[].hostkey' <<<"$body"
}

# ---- 1. Find the host(s) --------------------------------------------------
HOSTS_BEFORE=$(list_hosts)
DELETED_BEFORE=$(list_deleted)
KEYS=$(awk -F'\t' -v h="$TARGET" '$2 == h {print $1}' <<<"$HOSTS_BEFORE")

if [ -z "$KEYS" ]; then
    die "no host with hostname exactly '$TARGET' found in Mission Portal; nothing changed"
fi

OTHER_ACTIVE=$(awk -F'\t' -v h="$TARGET" '$2 != h {print $1}' <<<"$HOSTS_BEFORE" | sort -u)
OTHER_DELETED=$(grep -vxF -f <(echo "$KEYS") <<<"$DELETED_BEFORE" | sort -u || true)

echo "Found $(wc -l <<<"$KEYS") host record(s) with hostname '$TARGET':"
sed 's/^/  /' <<<"$KEYS"

# ---- 2. Soft-delete via API ----------------------------------------------
for key in $KEYS; do
    body=$(api DELETE "/api/host/$key")
    code=$(cat "$WORK/code")
    case $code in 200|202|204) echo "Deleted $key (HTTP $code)";;
                  *) die "DELETE /api/host/$key failed (HTTP $code): $body";; esac
done

# Wait until each key shows up in the deleted-hosts list.
for key in $KEYS; do
    for i in $(seq 1 30); do
        list_deleted | grep -qxF "$key" && break
        [ "$i" = 30 ] && die "$key never appeared in deleted hosts list"
        sleep 2
    done
done

# ---- 3. Purge from deleted hosts (Mission Portal web session) ------------
login_page=$(curl -sk -c "$CJ" -b "$CJ" "$MP_URL/login/index") || die "cannot reach login page"
csrf=$(grep -oE 'name="ci_csrf_token"[^>]*' <<<"$login_page" | grep -oE 'value="[^"]*"' | head -1 | cut -d'"' -f2)
[ -n "$csrf" ] || csrf=$(grep -oE 'value="[0-9a-f]{32}"' <<<"$login_page" | head -1 | cut -d'"' -f2)
[ -n "$csrf" ] || die "could not obtain CSRF token from login page"
curl -sk -c "$CJ" -b "$CJ" -o /dev/null "$MP_URL/login/index" \
    --data-urlencode "ci_csrf_token=$csrf" -d type_form=login \
    --data-urlencode "username=$MP_USER" --data-urlencode "password=$MP_PASSWORD" \
    -d timezone=UTC || die "login request failed"
landing=$(curl -sk -c "$CJ" -b "$CJ" -L -o /dev/null -w '%{url_effective}' "$MP_URL/")
case $landing in *login*) die "Mission Portal web login failed for user $MP_USER";; esac
csrf=$(awk '$6 == "ci_csrf_token" {print $7}' "$CJ" | tail -1)

for key in $KEYS; do
    code=$(curl -sk -c "$CJ" -b "$CJ" -X DELETE -o "$WORK/body" -w '%{http_code}' \
        -H 'X-Requested-With: XMLHttpRequest' -H "X-CSRF-TOKEN: $csrf" \
        -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
        "$MP_URL/host/delete_host_permanently/$key")
    case $code in 200|202|204) echo "Permanently deleted $key (HTTP $code)";;
                  *) die "permanent delete of $key failed (HTTP $code): $(cat "$WORK/body")";; esac
done

# ---- 4. Verify -----------------------------------------------------------
for i in $(seq 1 30); do
    HOSTS_AFTER=$(list_hosts)
    DELETED_AFTER=$(list_deleted)
    left_active=$(awk -F'\t' -v h="$TARGET" '$2 == h {print $1}' <<<"$HOSTS_AFTER"
                  cut -f1 <<<"$HOSTS_AFTER" | grep -xF -f <(echo "$KEYS") || true)
    left_deleted=$(grep -xF -f <(echo "$KEYS") <<<"$DELETED_AFTER" || true)
    [ -z "$left_active$left_deleted" ] && break
    [ "$i" = 30 ] && die "host still present after removal (active: ${left_active:-none}; deleted: ${left_deleted:-none})"
    sleep 2
done

missing_active=$(comm -23 <(echo "$OTHER_ACTIVE") <(cut -f1 <<<"$HOSTS_AFTER" | sort -u) | grep . || true)
missing_deleted=$(comm -23 <(echo "$OTHER_DELETED") <(sort -u <<<"$DELETED_AFTER") | grep . || true)
[ -z "$missing_active" ] || die "other active hosts disappeared: $missing_active"
[ -z "$missing_deleted" ] || die "other deleted hosts disappeared: $missing_deleted"

echo "Verified: '$TARGET' is in neither the host list nor the deleted hosts list;"
echo "all $(grep -c . <<<"$OTHER_ACTIVE" || true) other active and $(grep -c . <<<"$OTHER_DELETED" || true) other deleted host(s) are untouched."
exit 0
```