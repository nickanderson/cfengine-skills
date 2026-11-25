#!/usr/bin/env bash
#
# remove-host.sh <hostname>
#
# Completely removes a host from CFEngine Enterprise Mission Portal:
# soft-deletes it (which purges its reporting data) and then permanently
# deletes the resulting "deleted host" entry, so the host ends up in
# neither the active host list nor the deleted-hosts list.
#
# Requires MP_URL, MP_USER, MP_PASSWORD in the environment, and curl + jq
# on PATH. The hub's certificate is self-signed, so TLS verification is
# disabled (curl -k) when talking to it.

set -euo pipefail

usage() {
  echo "Usage: $0 <hostname>" >&2
}

if [ "$#" -ne 1 ]; then
  usage
  exit 1
fi

target_hostname=$1

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

mp_url=${MP_URL%/}

# api METHOD PATH -> prints "<http_status>\n<body>"
api() {
  local method=$1 path=$2 tmp status
  tmp=$(mktemp)
  status=$(curl -sk -u "${MP_USER}:${MP_PASSWORD}" -X "$method" \
    -o "$tmp" -w '%{http_code}' "${mp_url}${path}")
  printf '%s\n' "$status"
  cat "$tmp"
  rm -f "$tmp"
}

# urlencode STR -> percent-encoded string, safe to embed in a URL path segment
urlencode() {
  jq -rn --arg s "$1" '$s|@uri'
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

# 1. Locate the host by an exact hostname match.
list_out=$(api GET "/api/host?count=1000")
list_status=$(printf '%s\n' "$list_out" | head -n1)
list_body=$(printf '%s\n' "$list_out" | tail -n+2)

[ "$list_status" = "200" ] || fail "failed to list hosts (HTTP $list_status): $list_body"

host_id=$(printf '%s' "$list_body" | jq -r --arg h "$target_hostname" \
  '[.data[] | select(.hostname == $h)] | if length == 1 then .[0].id elif length == 0 then "" else "AMBIGUOUS" end')

if [ -z "$host_id" ]; then
  fail "no host with hostname '${target_hostname}' found in Mission Portal"
fi
if [ "$host_id" = "AMBIGUOUS" ]; then
  fail "multiple hosts with hostname '${target_hostname}' found; refusing to guess which to remove"
fi

encoded_id=$(urlencode "$host_id")

echo "Found host '${target_hostname}' (id ${host_id})" >&2

# 2. Soft-delete: purges reporting data and schedules key removal.
del_out=$(api DELETE "/api/host/${encoded_id}")
del_status=$(printf '%s\n' "$del_out" | head -n1)
del_body=$(printf '%s\n' "$del_out" | tail -n+2)

if [ "$del_status" != "202" ]; then
  fail "failed to delete host '${target_hostname}' (HTTP $del_status): $del_body"
fi
echo "Deleted host '${target_hostname}' from active inventory (HTTP 202)" >&2

# 3. Wait for the host to show up in the deleted-hosts list, then purge it
#    permanently from there too (permanent deletion requires the host to
#    already be present in /api/hosts/deleted).
found_in_deleted=0
for _ in $(seq 1 30); do
  deleted_out=$(api GET "/api/hosts/deleted?limit=1000")
  deleted_status=$(printf '%s\n' "$deleted_out" | head -n1)
  deleted_body=$(printf '%s\n' "$deleted_out" | tail -n+2)
  [ "$deleted_status" = "200" ] || fail "failed to list deleted hosts (HTTP $deleted_status): $deleted_body"

  if printf '%s' "$deleted_body" | jq -e --arg id "$host_id" \
      '.data[] | select(.hostkey == $id)' >/dev/null; then
    found_in_deleted=1
    break
  fi
  sleep 1
done

[ "$found_in_deleted" -eq 1 ] || fail "host '${target_hostname}' never appeared in the deleted-hosts list"

perm_out=$(api DELETE "/api/hosts/delete-permanently/${encoded_id}")
perm_status=$(printf '%s\n' "$perm_out" | head -n1)
perm_body=$(printf '%s\n' "$perm_out" | tail -n+2)

if [ "$perm_status" != "200" ]; then
  fail "failed to permanently delete host '${target_hostname}' (HTTP $perm_status): $perm_body"
fi
echo "Permanently purged deleted-host entry for '${target_hostname}' (HTTP 200)" >&2

# 4. Verify the host is gone from both the active list and the deleted list.
final_list_out=$(api GET "/api/host?count=1000")
final_list_body=$(printf '%s\n' "$final_list_out" | tail -n+2)
if printf '%s' "$final_list_body" | jq -e --arg id "$host_id" \
    '.data[] | select(.id == $id)' >/dev/null; then
  fail "host '${target_hostname}' still appears in the active host list after deletion"
fi

final_deleted_out=$(api GET "/api/hosts/deleted?limit=1000")
final_deleted_body=$(printf '%s\n' "$final_deleted_out" | tail -n+2)
if printf '%s' "$final_deleted_body" | jq -e --arg id "$host_id" \
    '.data[] | select(.hostkey == $id)' >/dev/null; then
  fail "host '${target_hostname}' still appears in the deleted-hosts list after deletion"
fi

echo "Verified: '${target_hostname}' is present in neither the host list nor the deleted-hosts list." >&2
exit 0
