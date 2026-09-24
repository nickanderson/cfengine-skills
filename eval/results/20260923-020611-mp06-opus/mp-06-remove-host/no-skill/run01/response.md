I wrote `remove-host.sh`, but when I ran it for `decomm01.example.com` it exited 1: the host was already gone, because I had removed it by hand while working out which endpoints to use. So the script's own delete-and-verify path has never run from start to finish. Checked directly afterwards, the host is in neither the host list nor deleted hosts, and nothing else was changed.

## What happened

- **Hosts at the start:** `decomm01.example.com` had key `SHA=evaldel1790147185x1`. There was also a similarly named `lab-decomm01.example.com` (key `…x2`) and one host that was already deleted (key `SHA=d2224f…`). Neither of those was touched.
- **Removing a host takes two steps:**
  1. `DELETE /api/host/<key>` moves the host to "deleted hosts". The listing is at `GET /api/hosts/deleted`.
  2. Permanent removal isn't in the REST API. The Mission Portal UI does it with `DELETE /host/delete_host_permanently/<key>`, which needs a logged-in browser session. I found this in the UI's JavaScript.
- **Removal by hand:** I ran both steps against `decomm01`'s key only.

## Run output

```
$ ./remove-host.sh decomm01.example.com
ERROR: no host with hostname exactly 'decomm01.example.com' found; nothing changed
exit=1
$ ./remove-host.sh decomm01
ERROR: no host with hostname exactly 'decomm01' found; nothing changed
exit=1
```

Checked afterwards: the host list has host001, host004 ×2, hub ×2 and lab-decomm01. Deleted hosts has only the host that was already there (`SHA=d2224f…`).

## What the script does

1. It pages through the whole host list and picks only hosts whose hostname matches the argument exactly. If there are none, it prints an error to stderr, changes nothing, and exits 1.
2. For each match, it deletes the host through the API and waits for it to appear in deleted hosts. It then logs in to Mission Portal and deletes it permanently.
3. It exits 0 only after checking that the host is in neither list. It also compares every other host and every other deleted host against a snapshot taken at the start; if anything else changed, it reports an error and exits 1.

If several records share the exact hostname (as `host004.example.com` does here), the script removes all of them.

```bash
#!/usr/bin/env bash
# remove-host.sh HOSTNAME
# Completely remove every host record whose hostname is exactly HOSTNAME from
# CFEngine Enterprise Mission Portal: delete it (API), then permanently delete
# it from "deleted hosts" (Mission Portal route), then verify it is gone.
#
# Requires: MP_URL, MP_USER, MP_PASSWORD in the environment; curl, python3.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

[ $# -eq 1 ] && [ -n "$1" ] || die "usage: $0 HOSTNAME"
TARGET=$1
: "${MP_URL:?MP_URL not set}" "${MP_USER:?MP_USER not set}" "${MP_PASSWORD:?MP_PASSWORD not set}"
MP_URL=${MP_URL%/}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
JAR=$WORK/cookies

api() { # api METHOD PATH -> body on stdout, fails on HTTP >= 400
  curl -sSk --fail -u "$MP_USER:$MP_PASSWORD" -X "$1" "$MP_URL$2"
}

# All hosts as "hostkey<TAB>hostname" lines (follows pagination).
list_hosts() {
  local page=1 out
  while :; do
    out=$(api GET "/api/host?count=500&page=$page") || return 1
    printf '%s' "$out" | python3 -c '
import json,sys
d=json.load(sys.stdin)
for h in d["data"]: print("%s\t%s" % (h["id"], h.get("hostname") or ""))
m=d["meta"]; sys.exit(0 if m["page"]*m["count"] < m["total"] and d["data"] else 3)' && page=$((page+1)) && continue
    [ $? -eq 3 ] && return 0 || return 1
  done
}

# All deleted-host keys, one per line.
list_deleted() {
  api GET "/api/hosts/deleted" | python3 -c '
import json,sys
for h in json.load(sys.stdin)["data"]: print(h["hostkey"])'
}

# ---- find exact matches -----------------------------------------------------
list_hosts > "$WORK/hosts_before" || die "could not list hosts from $MP_URL"
list_deleted > "$WORK/deleted_before" || die "could not list deleted hosts"
awk -F'\t' -v h="$TARGET" '$2 == h {print $1}' "$WORK/hosts_before" > "$WORK/keys"

if [ ! -s "$WORK/keys" ]; then
  die "no host with hostname exactly '$TARGET' found; nothing changed"
fi
mapfile -t KEYS < "$WORK/keys"
echo "Found ${#KEYS[@]} host record(s) with hostname '$TARGET':"
printf '  %s\n' "${KEYS[@]}"

# Snapshot of everything else, used to prove no other host was affected.
awk -F'\t' -v h="$TARGET" '$2 != h {print $1}' "$WORK/hosts_before" | sort > "$WORK/others_before"
grep -vxF -f "$WORK/keys" "$WORK/deleted_before" | sort > "$WORK/others_deleted_before" || true

# ---- Mission Portal session (permanent delete is not exposed in /api) --------
login() {
  local token
  token=$(curl -sSk -c "$JAR" -b "$JAR" "$MP_URL/login/index" |
          sed -n 's/.*name="ci_csrf_token" value="\([^"]*\)".*/\1/p' | head -1)
  [ -n "$token" ] || return 1
  curl -sSk -c "$JAR" -b "$JAR" -o /dev/null "$MP_URL/login/index" \
    --data-urlencode "ci_csrf_token=$token" --data-urlencode "type_form=login" \
    --data-urlencode "username=$MP_USER" --data-urlencode "password=$MP_PASSWORD" \
    --data-urlencode "timezone=UTC"
  # Logged in if the dashboard does not bounce us back to /login.
  local eff
  eff=$(curl -sSk -L -c "$JAR" -b "$JAR" -o /dev/null -w '%{url_effective}' "$MP_URL/dashboard")
  [[ $eff != */login* ]]
}
login || die "Mission Portal login failed for user $MP_USER"
CSRF=$(awk '$6 == "csrf_token" {print $7}' "$JAR" | tail -1)

wait_until() { # wait_until SECONDS CMD... ; retries CMD every 2s
  local end=$((SECONDS + $1)); shift
  until "$@"; do [ $SECONDS -ge $end ] && return 1; sleep 2; done
}
in_deleted() { list_deleted | grep -qxF "$1"; }

# ---- delete ------------------------------------------------------------------
for key in "${KEYS[@]}"; do
  echo "Deleting $key ..."
  api DELETE "/api/host/$key" > /dev/null || die "DELETE /api/host/$key failed"
  wait_until 60 in_deleted "$key" || die "$key did not appear in deleted hosts"
  code=$(curl -sSk -c "$JAR" -b "$JAR" -o "$WORK/perm.out" -w '%{http_code}' -X DELETE \
           -H 'X-Requested-With: XMLHttpRequest' -H "X-CSRF-TOKEN: $CSRF" \
           "$MP_URL/host/delete_host_permanently/$key")
  [[ $code == 2* ]] || die "permanent delete of $key failed (HTTP $code): $(cat "$WORK/perm.out")"
  echo "  permanently deleted (HTTP $code)"
done

# ---- verify ------------------------------------------------------------------
fully_gone() {
  list_hosts > "$WORK/hosts_after" && list_deleted > "$WORK/deleted_after" || return 1
  ! awk -F'\t' '{print $1}' "$WORK/hosts_after" | grep -qxF -f "$WORK/keys" &&
  ! awk -F'\t' -v h="$TARGET" '$2 == h {f=1} END {exit !f}' "$WORK/hosts_after" &&
  ! grep -qxF -f "$WORK/keys" "$WORK/deleted_after"
}
wait_until 60 fully_gone || die "verification failed: '$TARGET' still present in host list or deleted hosts"

awk -F'\t' '{print $1}' "$WORK/hosts_after" | sort > "$WORK/others_after"
sort "$WORK/deleted_after" > "$WORK/others_deleted_after"
cmp -s "$WORK/others_before" "$WORK/others_after" ||
  die "other hosts changed in host list: $(comm -3 "$WORK/others_before" "$WORK/others_after" | tr -s '\t\n' '  ')"
cmp -s "$WORK/others_deleted_before" "$WORK/others_deleted_after" ||
  die "deleted-hosts list changed for other hosts: $(comm -3 "$WORK/others_deleted_before" "$WORK/others_deleted_after" | tr -s '\t\n' '  ')"

echo "Verified: '$TARGET' is in neither the host list nor deleted hosts;" \
     "$(wc -l < "$WORK/others_after") other host(s) and $(wc -l < "$WORK/others_deleted_after") other deleted host(s) unchanged."
exit 0
```

To test the full delete path, run it against a throwaway host you add to the hub for that purpose. I didn't want to delete a real host just to test it.