The script is in place, executable, and verified against the live hub. It found `decomm01.example.com`'s hostkey, marked it deleted, waited for it to appear in the deleted-hosts list, permanently deleted it, then confirmed it's absent from both the host list and the deleted-hosts list before exiting 0 — while leaving the similarly-named `lab-decomm01.example.com` untouched. Running it again on the same (now-gone) hostname correctly errors to stderr and exits 1 without making any changes.

```bash
#!/usr/bin/env bash
#
# remove-host.sh <hostname>
#
# Removes a host from a CFEngine Enterprise Mission Portal hub completely:
# marks it deleted, permanently deletes its record, then verifies it is
# gone from both the host list and the deleted-hosts list before exiting.
#
# If no host has exactly the given hostname, nothing is changed, an error
# is printed to stderr, and the script exits 1.
#
# Required environment:
#   MP_URL       Mission Portal base URL, e.g. https://hub.example.com
#   MP_USER      Mission Portal username
#   MP_PASSWORD  Mission Portal password
# Optional:
#   MP_CACERT    Path to the hub's CA/server certificate. Without it,
#                TLS certificate verification is skipped (-k), which is
#                appropriate for a hub with a self-signed certificate.

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <hostname>" >&2
  exit 1
fi

target_hostname=$1

: "${MP_URL:?MP_URL is required}"
: "${MP_USER:?MP_USER is required}"
: "${MP_PASSWORD:?MP_PASSWORD is required}"

command -v curl >/dev/null 2>&1 || { echo "Error: curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq is required" >&2; exit 1; }

MP_URL=${MP_URL%/}

tls=(-k)
if [ -n "${MP_CACERT:-}" ]; then
  tls=(--cacert "$MP_CACERT")
fi

netrc_host="${MP_URL#*://}"
netrc_host="${netrc_host%%/*}"
netrc_host="${netrc_host%%:*}"

netrc_file=$(mktemp)
trap 'rm -f "$netrc_file"' EXIT
chmod 600 "$netrc_file"
printf 'machine %s\nlogin %s\npassword %s\n' "$netrc_host" "$MP_USER" "$MP_PASSWORD" > "$netrc_file"

http_code=""
resp_body=""

# call METHOD PATH [JSON-BODY]
# Performs the request, sets http_code and resp_body. Only aborts on a
# transport-level failure (curl itself failing); HTTP error statuses are
# left for the caller to inspect.
call() {
  local method="$1" path="$2" body="${3:-}"
  local -a curl_args=(-sS "${tls[@]}" --netrc-file "$netrc_file" -X "$method" -w '\n%{http_code}')
  if [ -n "$body" ]; then
    curl_args+=(-H 'Content-Type: application/json' --data-binary "$body")
  fi
  local raw rc=0
  raw=$(curl "${curl_args[@]}" "$MP_URL$path") || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "Error: request to $path failed (curl exit $rc)" >&2
    exit 1
  fi
  http_code="${raw##*$'\n'}"
  resp_body="${raw%$'\n'*}"
}

sql_escape() {
  printf '%s' "${1//\'/\'\'}"
}

# --- Step 1: find the host(s) with exactly this hostname ---

escaped_hostname=$(sql_escape "$target_hostname")
query="SELECT hostkey FROM hosts WHERE hostname = '${escaped_hostname}'"
query_body=$(jq -n --arg q "$query" '{query: $q}')

call POST /api/query "$query_body"
if [ "$http_code" != "200" ]; then
  echo "Error: failed to query Mission Portal for '$target_hostname' (HTTP $http_code): $resp_body" >&2
  exit 1
fi

mapfile -t hostkeys < <(printf '%s' "$resp_body" | jq -r '.data[0].rows[]? | .[0]')

if [ "${#hostkeys[@]}" -eq 0 ]; then
  echo "Error: no host with hostname '$target_hostname' found in Mission Portal" >&2
  exit 1
fi

# --- Step 2: mark each matching host deleted ---

for hk in "${hostkeys[@]}"; do
  call DELETE "/api/host/$hk"
  case "$http_code" in
    2??) ;;
    *) echo "Error: failed to delete host '$target_hostname' (key $hk, HTTP $http_code): $resp_body" >&2; exit 1 ;;
  esac
done

# --- Step 3: wait until each key shows up in the deleted hosts list ---

for hk in "${hostkeys[@]}"; do
  found=""
  for _ in $(seq 1 30); do
    call GET "/api/hosts/deleted?limit=100000"
    if [ "$http_code" = "200" ] && printf '%s' "$resp_body" | jq -e --arg hk "$hk" '.data[] | select(.hostkey == $hk)' >/dev/null 2>&1; then
      found=1
      break
    fi
    sleep 2
  done
  if [ -z "$found" ]; then
    echo "Error: host '$target_hostname' (key $hk) never appeared in the deleted hosts list" >&2
    exit 1
  fi
done

# --- Step 4: permanently delete each matching host ---

for hk in "${hostkeys[@]}"; do
  call DELETE "/api/hosts/delete-permanently/$hk"
  case "$http_code" in
    2??) ;;
    *) echo "Error: failed to permanently delete host '$target_hostname' (key $hk, HTTP $http_code): $resp_body" >&2; exit 1 ;;
  esac
done

# --- Step 5: verify the host is gone from both the host list and the deleted list ---

call POST /api/query "$query_body"
if [ "$http_code" != "200" ]; then
  echo "Error: failed to verify host list after deletion (HTTP $http_code): $resp_body" >&2
  exit 1
fi
remaining=$(printf '%s' "$resp_body" | jq -r '.data[0].rowCount // 0')
if [ "$remaining" != "0" ]; then
  echo "Error: host '$target_hostname' is still present in the host list after deletion" >&2
  exit 1
fi

call GET "/api/hosts/deleted?limit=100000"
if [ "$http_code" != "200" ]; then
  echo "Error: failed to verify deleted hosts list (HTTP $http_code): $resp_body" >&2
  exit 1
fi
for hk in "${hostkeys[@]}"; do
  if printf '%s' "$resp_body" | jq -e --arg hk "$hk" '.data[] | select(.hostkey == $hk)' >/dev/null 2>&1; then
    echo "Error: host '$target_hostname' (key $hk) is still present in the deleted hosts list" >&2
    exit 1
  fi
done

echo "Host '$target_hostname' has been completely removed from Mission Portal (verified absent from host list and deleted hosts list)."
exit 0
```

Output from `./remove-host.sh decomm01.example.com`:
```
Host 'decomm01.example.com' has been completely removed from Mission Portal (verified absent from host list and deleted hosts list).
```
Exit code: 0

Notes:
- Looks up the exact hostname via SQL (`hostname = '...'`) so a similarly-named host like `lab-decomm01.example.com` is never touched — confirmed by rerunning the query afterward.
- Handles the (unlikely) case of duplicate hostkeys sharing one hostname by removing all of them.
- Uses a `mktemp`'d, `chmod 600` netrc file for credentials (never on the command line); needs `MP_URL`/`MP_USER`/`MP_PASSWORD`, and skips TLS verification unless `MP_CACERT` is set, since the hub's certificate is self-signed.