decomm01.example.com has been removed from Mission Portal and is no longer among deleted hosts. The script checked both lists before exiting 0. I ran it on the hub with your `MP_URL`, `MP_USER` and `MP_PASSWORD`.

**Output of `./remove-host.sh decomm01.example.com`** (exit 0):
```
Found decomm01.example.com: SHA=evaldel1790147427x1
Deleted SHA=evaldel1790147427x1 from the host list
Permanently deleted SHA=evaldel1790147427x1 from deleted hosts
Verified: decomm01.example.com (SHA=evaldel1790147427x1) is in neither the host list nor deleted hosts
```

**No other host was affected.** I checked the hub separately afterwards:
- The host list went from 7 to 6. `lab-decomm01.example.com`, whose name contains the target, is still there, because the script only matches the exact hostname.
- The one host that was already among deleted hosts (`SHA=d2224f…`) is still there too.

**Error cases (all exit 1 and change nothing):**
- `decomm01` or `DECOMM01.example.com`: `remove-host: no host has hostname exactly '…'; nothing changed`.
- `nosuch.example.com`: the same message.
- No argument: `remove-host: usage: remove-host.sh HOSTNAME`.

**How it works:**
1. It reads the full host list, page by page, since the API returns only 50 hosts by default.
2. It deletes the host with `DELETE /api/host/:hostkey`.
3. It waits for the host to show up among deleted hosts, then removes it there with `DELETE /api/hosts/delete-permanently/:hostkey`.
4. It reads both lists again to confirm the host is gone from each.

It exits 2 if an API call or the final check fails.

**Things to know:**
- **Duplicate hostnames:** if more than one host has exactly the given name, the script also exits 1 and changes nothing. Your hub already has two hostnames used twice each (`host004.example.com` and `hub.example.com`), and deleting the wrong one would affect another machine.
- **Certificate:** the script skips certificate checks (`curl -k`) because the hub's certificate is self-signed. To turn checking on, set `MP_CACERT` to the path of the hub's certificate.
- **Password:** it's passed to curl on stdin, so it never appears in the process list.
- **Requires:** `curl` and `jq`.

```bash
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
```