Verified: `decomm01.example.com` is gone from both the host list and the deleted-hosts list, `lab-decomm01.example.com` (the similarly-named host) is untouched, and re-running the script against the now-removed host correctly errors out with exit 1 and no further changes.

## Output from running it

```
$ ./remove-host.sh decomm01.example.com
Found host 'decomm01.example.com' (hostkey SHA=evaldel1790153335x1); deleting...
Host 'decomm01.example.com' (SHA=evaldel1790153335x1) has been completely removed from Mission Portal.
$ echo $?
0
```

## `remove-host.sh`

```bash
#!/usr/bin/env bash
# Completely remove a host from CFEngine Mission Portal by exact hostname.
#
# Usage: remove-host.sh <hostname>
#
# Requires environment variables:
#   MP_URL       Base URL of the Mission Portal API, e.g. https://hub.example.com
#   MP_USER      Mission Portal username
#   MP_PASSWORD  Mission Portal password
# Optional:
#   MP_CACERT    Path to the hub's CA/certificate to verify TLS with.
#                If unset, certificate verification is skipped (-k), which is
#                appropriate for a hub with a self-signed certificate that you
#                have not pinned locally.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <hostname>" >&2
  exit 1
fi
target_hostname=$1

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not found in PATH" >&2
  exit 1
fi

base_url=${MP_URL%/}

tls_opts=(-k)
if [ -n "${MP_CACERT:-}" ]; then
  tls_opts=(--cacert "$MP_CACERT")
fi

# mp <METHOD> <path> [extra curl args...]
# Auth is fed to curl via its stdin config (-K -) so the password never
# appears on the command line or in a temp file.
mp() {
  local method=$1 path=$2
  shift 2
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
    curl -sS --fail-with-body "${tls_opts[@]}" -K - -X "$method" "$@" "$base_url$path"
}

# Look up the exact host by hostname via the reporting SQL view, which
# excludes already-deleted hosts and applies RBAC.
sql_escaped=${target_hostname//\'/\'\'}
query="SELECT hostkey, hostname FROM hosts WHERE hostname = '$sql_escaped'"
query_json=$(jq -n --arg q "$query" '{query: $q}')

lookup=$(mp POST /api/query -H 'Content-Type: application/json' --data-binary "$query_json")

row_count=$(printf '%s' "$lookup" | jq -r '.data[0].rowCount')

if [ "$row_count" -eq 0 ]; then
  echo "Error: no host with hostname '$target_hostname' found in Mission Portal" >&2
  exit 1
fi

if [ "$row_count" -ne 1 ]; then
  echo "Error: expected exactly one host named '$target_hostname', found $row_count; not touching anything" >&2
  exit 1
fi

hostkey=$(printf '%s' "$lookup" | jq -r '.data[0].rows[0][0]')

echo "Found host '$target_hostname' (hostkey $hostkey); deleting..." >&2

# Step 1: soft-delete. This purges reporting data immediately and schedules
# the hostkey for full removal.
mp DELETE "/api/host/$hostkey" >/dev/null

# Step 2: wait for the host to show up in the deleted-hosts list, which is
# a prerequisite for permanent deletion.
deadline=$((SECONDS + 900))
in_deleted_list=0
while [ "$SECONDS" -lt "$deadline" ]; do
  deleted=$(mp GET "/api/hosts/deleted?limit=100000")
  if printf '%s' "$deleted" | jq -e --arg hk "$hostkey" '.data[] | select(.hostkey == $hk)' >/dev/null; then
    in_deleted_list=1
    break
  fi
  sleep 3
done

if [ "$in_deleted_list" -ne 1 ]; then
  echo "Error: host '$target_hostname' ($hostkey) never appeared in the deleted-hosts list; giving up" >&2
  exit 1
fi

# Step 3: permanently delete the deleted-host record.
mp DELETE "/api/hosts/delete-permanently/$hostkey" >/dev/null

# Step 4: verify the host is completely gone: neither in the active host
# list nor among deleted hosts.
still_active=$(mp POST /api/query -H 'Content-Type: application/json' \
  --data-binary "$(jq -n --arg q "$query" '{query: $q}')" | jq -r '.data[0].rowCount')

still_deleted=$(mp GET "/api/hosts/deleted?limit=100000" |
  jq -e --arg hk "$hostkey" '[.data[] | select(.hostkey == $hk)] | length')

if [ "$still_active" -ne 0 ] || [ "$still_deleted" -ne 0 ]; then
  echo "Error: host '$target_hostname' ($hostkey) still present after deletion (active rows: $still_active, deleted rows: $still_deleted)" >&2
  exit 1
fi

echo "Host '$target_hostname' ($hostkey) has been completely removed from Mission Portal." >&2
exit 0
```

Notes:
- Credentials are read only from `MP_URL`/`MP_USER`/`MP_PASSWORD` (optionally `MP_CACERT` for cert pinning) — never hardcoded, and passed to curl via its stdin config so the password doesn't appear on the command line.
- Without `MP_CACERT` it skips certificate verification (`-k`), appropriate for the self-signed cert mentioned; supply `MP_CACERT` to verify against a pinned certificate instead.
- Matching is by exact SQL equality on `hostname`, so `lab-decomm01.example.com` (confirmed present on this hub) is never touched.
- It performs the two-step delete (soft-delete, then permanent-delete once the host appears in `/api/hosts/deleted`) and only exits 0 after re-querying both the active list and the deleted list to confirm the host is gone from each.