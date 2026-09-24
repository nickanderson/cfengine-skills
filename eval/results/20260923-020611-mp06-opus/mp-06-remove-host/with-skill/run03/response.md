I ran `remove-host.sh` for decomm01.example.com and it exited 0. The host is gone from both the host list and the deleted hosts, and no other host changed.

**Output of the run:**
```
$ ./remove-host.sh decomm01.example.com
Found decomm01.example.com: SHA=evaldel1790148282x1
Deleted host SHA=evaldel1790148282x1
Permanently deleted host record SHA=evaldel1790148282x1
Verified: decomm01.example.com (SHA=evaldel1790148282x1) is in neither the host list nor deleted hosts; 6 other hosts and 1 deleted host(s) unchanged.
exit=0
```

I then checked the hub separately:
- **Host list:** 6 hosts. `lab-decomm01.example.com` is still there; it contains the name but isn't an exact match, so the script left it alone.
- **Deleted hosts:** only the host that was already there before (`SHA=d2224f…`).
- **Running the script again** now prints `no host has exactly the hostname 'decomm01.example.com'; nothing changed` to stderr and exits 1. Near-misses (`decomm01`, `DECOMM01.example.com`) also exit 1 without changing anything.

**How it works:**
- It pages through `/api/host` to get every host and looks for an exact, case-sensitive hostname match.
- If it finds exactly one match, it deletes that host with `DELETE /api/host/:hostkey`.
- It waits for the host to show up in `/api/hosts/deleted`, then removes that record with `DELETE /api/hosts/delete-permanently/:hostkey`. A normal delete leaves a record in the deleted-hosts list, and this second call removes it.
- It exits 0 only after checking three things: the hostkey and hostname are gone from the host list, the hostkey is gone from deleted hosts, and every other host (active or deleted) is exactly as it was before.

**Behaviour to know about:**
- **Certificate:** it skips certificate verification (`curl -k`) because your hub's certificate is self-signed. Set `MP_CACERT=/path/to/hub-cert.pem` to verify it instead.
- **Credentials:** the password is passed to curl on stdin, so it never appears on a command line.
- **Duplicate hostnames:** if more than one host has the name, the script changes nothing and exits 1. This matters on your hub because `host004` and `hub.example.com` each appear twice.
- **API or verification failures:** these exit 2, which is different from the "no such host" exit 1.

**`remove-host.sh`** (saved in the working directory):
```bash
#!/usr/bin/env bash
# remove-host.sh HOSTNAME
#
# Completely removes one host from CFEngine Enterprise Mission Portal:
#   1. DELETE /api/host/:hostkey                  (host -> deleted hosts)
#   2. DELETE /api/hosts/delete-permanently/:key  (purge the deleted-host record)
# then verifies the host is in neither the host list nor the deleted hosts,
# and that no other host (active or deleted) was affected.
#
# Environment:
#   MP_URL       e.g. https://hub.example.com
#   MP_USER      Mission Portal user
#   MP_PASSWORD  Mission Portal password
#   MP_CACERT    optional: hub CA/certificate file; without it TLS
#                verification is skipped (-k), as the hub cert is self-signed.
#
# Exit: 0 host verified gone; 1 usage/no exact match/ambiguous (nothing changed);
#       2 API error or verification failure.

set -euo pipefail

die() { local rc=$1; shift; echo "remove-host: error: $*" >&2; exit "$rc"; }

[ $# -eq 1 ] && [ -n "$1" ] || die 1 "usage: $0 HOSTNAME"
TARGET=$1

for v in MP_URL MP_USER MP_PASSWORD; do
    [ -n "${!v:-}" ] || die 1 "environment variable $v is not set"
done
command -v jq >/dev/null || die 1 "jq is required"
command -v curl >/dev/null || die 1 "curl is required"

MP_URL=${MP_URL%/}
if [ -n "${MP_CACERT:-}" ]; then
    TLS=(--cacert "$MP_CACERT")
else
    TLS=(-k)
fi

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

# api METHOD PATH -> body on stdout; returns non-zero on HTTP/transport error.
# Credentials go to curl on stdin (config), never on the command line.
api() {
    local method=$1 path=$2 code
    code=$(printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
        curl -sS "${TLS[@]}" -K - -X "$method" -o "$TMP" -w '%{http_code}' \
            "$MP_URL$path") || { echo "remove-host: curl failed: $method $path" >&2; return 3; }
    if [[ $code != 2?? ]]; then
        echo "remove-host: HTTP $code for $method $path: $(head -c 500 "$TMP")" >&2
        return 2
    fi
    cat "$TMP"
}

# All active hosts as TSV "hostkey<TAB>hostname", paging until meta.total.
list_hosts() {
    local page=1 count=100 got=0 total body
    while :; do
        body=$(api GET "/api/host?page=$page&count=$count") || return
        total=$(jq -r '.meta.total' <<<"$body")
        jq -r '.data[] | [.id, (.hostname // "")] | @tsv' <<<"$body"
        got=$((got + $(jq '.data | length' <<<"$body")))
        [ "$got" -lt "$total" ] && [ "$(jq '.data | length' <<<"$body")" -gt 0 ] || break
        page=$((page + 1))
    done
}

# All deleted hostkeys, one per line (no limit => all of them).
list_deleted() {
    api GET "/api/hosts/deleted" | jq -r '.data[].hostkey'
}

# --- Find the host -------------------------------------------------------
hosts_before=$(list_hosts) || die 2 "could not list hosts"
deleted_before=$(list_deleted) || die 2 "could not list deleted hosts"

matches=$(awk -F'\t' -v h="$TARGET" '$2 == h { print $1 }' <<<"$hosts_before")
n=$(grep -c . <<<"$matches" || true)

if [ "$n" -eq 0 ]; then
    die 1 "no host has exactly the hostname '$TARGET'; nothing changed"
elif [ "$n" -gt 1 ]; then
    die 1 "$n hosts have the hostname '$TARGET' ($(tr '\n' ' ' <<<"$matches")); refusing to guess, nothing changed"
fi
KEY=$matches
echo "Found $TARGET: $KEY"

# --- Delete, then purge the deleted-host record --------------------------
api DELETE "/api/host/$KEY" >/dev/null || die 2 "DELETE /api/host/$KEY failed"
echo "Deleted host $KEY"

# Wait for it to show up among deleted hosts (required before permanent deletion).
for _ in $(seq 1 30); do
    list_deleted | grep -qxF "$KEY" && break
    sleep 2
done
list_deleted | grep -qxF "$KEY" || die 2 "$KEY did not appear in deleted hosts; cannot purge"

api DELETE "/api/hosts/delete-permanently/$KEY" >/dev/null ||
    die 2 "permanent deletion of $KEY failed"
echo "Permanently deleted host record $KEY"

# --- Verify ---------------------------------------------------------------
hosts_after=$(list_hosts) || die 2 "could not list hosts for verification"
deleted_after=$(list_deleted) || die 2 "could not list deleted hosts for verification"

fail=0
if cut -f1 <<<"$hosts_after" | grep -qxF "$KEY"; then
    echo "remove-host: verify: $KEY still in host list" >&2; fail=1
fi
if awk -F'\t' -v h="$TARGET" '$2 == h { f=1 } END { exit !f }' <<<"$hosts_after"; then
    echo "remove-host: verify: a host named $TARGET is still in host list" >&2; fail=1
fi
if grep -qxF "$KEY" <<<"$deleted_after"; then
    echo "remove-host: verify: $KEY still among deleted hosts" >&2; fail=1
fi
# No other host affected: every other active host is still active with the
# same hostname, and the deleted-hosts list is unchanged.
expected_hosts=$(grep -vF "$KEY"$'\t' <<<"$hosts_before" | sort)
if [ "$expected_hosts" != "$(sort <<<"$hosts_after")" ]; then
    echo "remove-host: verify: other active hosts changed:" >&2
    diff <(echo "$expected_hosts") <(sort <<<"$hosts_after") >&2 || true
    fail=1
fi
if [ "$(sort <<<"$deleted_before")" != "$(sort <<<"$deleted_after")" ]; then
    echo "remove-host: verify: deleted-hosts list changed for other hosts:" >&2
    diff <(sort <<<"$deleted_before") <(sort <<<"$deleted_after") >&2 || true
    fail=1
fi
[ "$fail" -eq 0 ] || die 2 "verification failed for $TARGET ($KEY)"

echo "Verified: $TARGET ($KEY) is in neither the host list nor deleted hosts;" \
     "$(grep -c . <<<"$hosts_after") other hosts and $(grep -c . <<<"$deleted_after" || true) deleted host(s) unchanged."
exit 0
```

**Caveats:**
- **Machine still running:** the permanent delete also removes the record that stops the hub from collecting from that host's key. If decomm01 is actually still running, it could re-register when it next reports.
- **Hosts added during a run:** the "no other host affected" check compares the host list before and after. A host that registers in the middle of a run would make that check fail with exit 2, even though nothing went wrong.