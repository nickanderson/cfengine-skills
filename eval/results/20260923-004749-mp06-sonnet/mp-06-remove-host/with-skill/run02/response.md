The script is written to `remove-host.sh`, executable, and has been run successfully against `decomm01.example.com`.

Output from the run:
```
Removing host decomm01.example.com (SHA=evaldel1)...
Verified: decomm01.example.com is gone from the host list and from deleted hosts.
```
(exit code 0)

I confirmed afterward via read-only API calls that `decomm01.example.com` is absent from both `/api/host` and `/api/hosts/deleted`, while the similarly-named `lab-decomm01.example.com`, the two `hub.example.com`/`host001.example.com` hosts, and a pre-existing unrelated deleted-host record were all untouched.

How it works:
- Looks up the exact hostname via `/api/query` (`SELECT hostkey FROM hosts WHERE hostname = '...'`), SQL-escaped and matched exactly (so `lab-decomm01.example.com` isn't caught).
- Exits 1 with a stderr message, no changes, if no host matches.
- For each matching hostkey: `DELETE /api/host/:hostkey` (removes it from the live host list and purges reporting data), waits for it to appear in `/api/hosts/deleted`, then `DELETE /api/hosts/delete-permanently/:hostkey` to purge the deleted-host record too, polling after each step (up to 120s) to confirm state.
- Only exits 0 after re-querying both the host list and deleted-hosts list and confirming the host is in neither.

```bash
#!/usr/bin/env bash
# Remove a host from CFEngine Mission Portal completely: the reporting entry
# is deleted, and the resulting "deleted host" record is then purged too, so
# the host ends up in neither /api/host nor /api/hosts/deleted.
#
# Usage: remove-host.sh <hostname>
#
# Configuration (environment variables):
#   MP_URL       Mission Portal base URL, e.g. https://hub.example.com  (required)
#   MP_USER      Mission Portal username                                (required)
#   MP_PASSWORD  Mission Portal password                                (required)
#   MP_CACERT    Path to the hub's certificate, for a self-signed hub   (optional;
#                without it, certificate verification is skipped)
#
# Exit status: 0 once the host is confirmed gone from both the host list and
# the deleted-hosts list. 1 if no host has exactly that hostname, if required
# configuration is missing, or if removal could not be completed/verified.

set -uo pipefail

POLL_INTERVAL=3
POLL_TIMEOUT=120

die() {
  echo "remove-host: $*" >&2
  exit 1
}

[ $# -eq 1 ] || die "usage: $0 <hostname>"
TARGET_HOST=$1

[ -n "${MP_URL:-}" ] || die "MP_URL must be set"
[ -n "${MP_USER:-}" ] || die "MP_USER must be set"
[ -n "${MP_PASSWORD:-}" ] || die "MP_PASSWORD must be set"

BASE_URL=${MP_URL%/}

TLS_OPTS=()
if [ -n "${MP_CACERT:-}" ]; then
  TLS_OPTS=(--cacert "$MP_CACERT")
else
  TLS_OPTS=(-k)
fi

NETRC_FILE=$(mktemp)
BODY_FILE=$(mktemp)
STATUS_FILE=$(mktemp)
cleanup() { rm -f "$NETRC_FILE" "$BODY_FILE" "$STATUS_FILE"; }
trap cleanup EXIT

MP_HOST=$(printf '%s' "$BASE_URL" | sed -E 's#^[a-zA-Z]+://##; s#/.*##; s#:.*##')
printf 'machine %s login %s password %s\n' "$MP_HOST" "$MP_USER" "$MP_PASSWORD" > "$NETRC_FILE"
chmod 600 "$NETRC_FILE"

# api METHOD PATH [JSON-BODY] -> prints response body on stdout, writes the
# HTTP status to $STATUS_FILE (not a variable: callers often invoke this via
# command substitution, which runs it in a subshell).
api() {
  local method=$1 path=$2 body=${3-}
  local -a args
  args=(-sS -X "$method" --netrc-file "$NETRC_FILE" -o "$BODY_FILE" -w '%{http_code}'
        --connect-timeout 10 --max-time 60)
  [ -n "$body" ] && args+=(-H "Content-Type: application/json" --data-binary "$body")
  local status
  status=$(curl "${TLS_OPTS[@]}" "${args[@]}" "$BASE_URL$path")
  local rc=$?
  [ "$rc" -eq 0 ] || die "request to $method $path failed (curl exit $rc)"
  echo "$status" > "$STATUS_FILE"
  cat "$BODY_FILE"
}

sql_string_literal() {  # SQL-escape a value for use inside '...'
  printf "%s" "$1" | sed "s/'/''/g"
}

# Find every host whose hostname is an exact match (there should be exactly one,
# but duplicate-hostname hosts are handled too so none of them are left behind).
find_hostkeys() {
  local literal query payload response
  literal=$(sql_string_literal "$TARGET_HOST")
  query="SELECT hostkey FROM hosts WHERE hostname = '${literal}'"
  payload=$(jq -n --arg q "$query" '{query: $q}')
  response=$(api POST /api/query "$payload")
  local status; status=$(cat "$STATUS_FILE")
  [ "$status" = "200" ] || die "lookup query failed (HTTP $status): $response"
  echo "$response" | jq -r '.data[0].rows[]?[0]'
}

# True (exit 0) if the given hostname currently appears in the live host list.
hostname_in_host_list() {
  local literal query payload response count
  literal=$(sql_string_literal "$TARGET_HOST")
  query="SELECT hostkey FROM hosts WHERE hostname = '${literal}'"
  payload=$(jq -n --arg q "$query" '{query: $q}')
  response=$(api POST /api/query "$payload")
  local status; status=$(cat "$STATUS_FILE")
  [ "$status" = "200" ] || die "verification query failed (HTTP $status): $response"
  count=$(echo "$response" | jq -r '.data[0].rowCount')
  [ "$count" != "0" ]
}

# True (exit 0) if the given hostkey currently appears among deleted hosts.
hostkey_in_deleted_list() {
  local hostkey=$1 response status
  response=$(api GET /api/hosts/deleted)
  status=$(cat "$STATUS_FILE")
  [ "$status" = "200" ] || die "deleted-hosts query failed (HTTP $status): $response"
  echo "$response" | jq -e --arg hk "$hostkey" '.data | any(.hostkey == $hk)' > /dev/null
}

mapfile -t HOSTKEYS < <(find_hostkeys)
if [ "${#HOSTKEYS[@]}" -eq 0 ] || [ -z "${HOSTKEYS[0]}" ]; then
  die "no host with hostname '$TARGET_HOST' found"
fi

for HOSTKEY in "${HOSTKEYS[@]}"; do
  echo "Removing host $TARGET_HOST ($HOSTKEY)..."

  api DELETE "/api/host/$HOSTKEY" > /dev/null
  STATUS=$(cat "$STATUS_FILE")
  case "$STATUS" in
    202|204) ;;
    404) die "host $HOSTKEY disappeared before it could be deleted" ;;
    *) die "DELETE /api/host/$HOSTKEY failed (HTTP $STATUS)" ;;
  esac

  # Reporting data is purged immediately, but poll briefly for consistency.
  waited=0
  while hostname_in_host_list; do
    [ "$waited" -ge "$POLL_TIMEOUT" ] && die "host $TARGET_HOST still in host list after deletion"
    sleep "$POLL_INTERVAL"
    waited=$((waited + POLL_INTERVAL))
  done

  # The deleted-host record appears once the deletion is processed; wait for
  # it, then purge it permanently so the host also leaves /api/hosts/deleted.
  waited=0
  until hostkey_in_deleted_list "$HOSTKEY"; do
    [ "$waited" -ge "$POLL_TIMEOUT" ] && die "host $HOSTKEY never appeared among deleted hosts"
    sleep "$POLL_INTERVAL"
    waited=$((waited + POLL_INTERVAL))
  done

  api DELETE "/api/hosts/delete-permanently/$HOSTKEY" > /dev/null
  STATUS=$(cat "$STATUS_FILE")
  case "$STATUS" in
    200) ;;
    404) : ;; # already gone
    *) die "DELETE /api/hosts/delete-permanently/$HOSTKEY failed (HTTP $STATUS)" ;;
  esac

  waited=0
  while hostkey_in_deleted_list "$HOSTKEY"; do
    [ "$waited" -ge "$POLL_TIMEOUT" ] && die "host $HOSTKEY still among deleted hosts after permanent deletion"
    sleep "$POLL_INTERVAL"
    waited=$((waited + POLL_INTERVAL))
  done
done

# Final confirmation: the hostname is gone from the live host list.
if hostname_in_host_list; then
  die "host $TARGET_HOST still appears in the host list"
fi

echo "Verified: $TARGET_HOST is gone from the host list and from deleted hosts."
```

Note: it uses `-k` (skip certificate verification) unless you set `MP_CACERT` to the hub's certificate file, since the hub uses a self-signed certificate.