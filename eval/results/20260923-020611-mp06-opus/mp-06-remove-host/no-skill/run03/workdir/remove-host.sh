#!/usr/bin/env bash
# remove-host.sh HOSTNAME
# Completely remove a host from CFEngine Enterprise Mission Portal:
#   1. soft-delete it via the API        (DELETE /api/host/<hostkey>)
#   2. purge it from the deleted hosts   (DELETE /host/delete_host_permanently/<hostkey>, MP UI endpoint)
#   3. verify it is in neither the host list nor the deleted-hosts list
# Requires: MP_URL, MP_USER, MP_PASSWORD; curl, jq.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

[ $# -eq 1 ] && [ -n "$1" ] || die "usage: $0 HOSTNAME"
HOSTNAME_ARG=$1
: "${MP_URL:?MP_URL not set}" "${MP_USER:?MP_USER not set}" "${MP_PASSWORD:?MP_PASSWORD not set}"
command -v jq >/dev/null || die "jq is required"
MP_URL=${MP_URL%/}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
COOKIES=$TMP/cookies

api() { # api METHOD PATH -> body on stdout, HTTP code in $TMP/code
  curl -sSk -u "$MP_USER:$MP_PASSWORD" -X "$1" -o "$TMP/body" -w '%{http_code}' "$MP_URL$2" >"$TMP/code" || die "curl $1 $2 failed"
  cat "$TMP/body"
}

# All hostkeys whose hostname is exactly $1 (paginated).
hostkeys_for() {
  local page=1 count=500 total body
  while :; do
    body=$(api GET "/api/host?count=$count&page=$page")
    [ "$(cat "$TMP/code")" = 200 ] || die "listing hosts failed (HTTP $(cat "$TMP/code")): $body"
    jq -r --arg h "$1" '.data[] | select(.hostname == $h) | .id' <<<"$body"
    total=$(jq -r '.meta.total' <<<"$body")
    [ $((page * count)) -lt "$total" ] || break
    page=$((page + 1))
  done
}

deleted_hostkeys() {
  local body
  body=$(api GET "/api/hosts/deleted")
  [ "$(cat "$TMP/code")" = 200 ] || die "listing deleted hosts failed (HTTP $(cat "$TMP/code")): $body"
  jq -r '.data[].hostkey' <<<"$body"
}

# Mission Portal web session (the permanent purge is only exposed through the UI controller).
mp_login() {
  local tok code
  curl -sSk -c "$COOKIES" -b "$COOKIES" -o "$TMP/login.html" "$MP_URL/login/index" || die "cannot reach login page"
  tok=$(sed -n 's/.*name="ci_csrf_token" value="\([^"]*\)".*/\1/p' "$TMP/login.html" | head -1)
  [ -n "$tok" ] || die "could not obtain CSRF token from login page"
  curl -sSk -c "$COOKIES" -b "$COOKIES" -o /dev/null \
    --data-urlencode "username=$MP_USER" --data-urlencode "password=$MP_PASSWORD" \
    --data-urlencode "ci_csrf_token=$tok" -d 'timezone=0&type_form=' "$MP_URL/login/index" || die "login failed"
  code=$(curl -sSk -b "$COOKIES" -o "$TMP/home.html" -w '%{http_code}' "$MP_URL/reports/health-diagnostic/deleted-hosts")
  if [ "$code" != 200 ] || grep -q 'document.location.href = "/login/index"' "$TMP/home.html"; then
    die "Mission Portal web login failed"
  fi
}

purge_deleted() { # purge_deleted HOSTKEY
  local csrf code
  csrf=$(awk '$6 == "ci_csrf_token" {print $7}' "$COOKIES" | tail -1)
  code=$(curl -sSk -b "$COOKIES" -c "$COOKIES" -X DELETE -o "$TMP/purge" -w '%{http_code}' \
    -H 'X-Requested-With: XMLHttpRequest' -H "X-CSRF-TOKEN: $csrf" \
    -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
    --data-urlencode "ci_csrf_token=$csrf" \
    "$MP_URL/host/delete_host_permanently/$1")
  case $code in 2??) ;; *) die "permanent delete of $1 failed (HTTP $code): $(cat "$TMP/purge")" ;; esac
}

# --- identify ---------------------------------------------------------------
mapfile -t KEYS < <(hostkeys_for "$HOSTNAME_ARG")
[ "${#KEYS[@]}" -gt 0 ] || die "no host with hostname exactly '$HOSTNAME_ARG' found in Mission Portal; nothing changed"
echo "Found ${#KEYS[@]} host(s) named '$HOSTNAME_ARG': ${KEYS[*]}"

mp_login

for key in "${KEYS[@]}"; do
  # --- soft delete ----------------------------------------------------------
  api DELETE "/api/host/$key" >/dev/null
  code=$(cat "$TMP/code")
  case $code in 2??) echo "Deleted $key from host list (HTTP $code)";; *) die "DELETE /api/host/$key failed (HTTP $code): $(cat "$TMP/body")";; esac

  # --- wait for it to reach the deleted list, then purge ---------------------
  for _ in $(seq 1 30); do
    deleted_hostkeys | grep -qxF "$key" && break
    sleep 2
  done
  purge_deleted "$key"
  echo "Purged $key from deleted hosts"
done

# --- verify -----------------------------------------------------------------
for _ in $(seq 1 30); do
  ok=1
  [ -z "$(hostkeys_for "$HOSTNAME_ARG")" ] || ok=0
  dels=$(deleted_hostkeys)
  for key in "${KEYS[@]}"; do
    grep -qxF "$key" <<<"$dels" && ok=0
    api GET "/api/host/$key" >/dev/null
    [ "$(cat "$TMP/code")" = 404 ] || ok=0
  done
  if [ $ok = 1 ]; then
    echo "Verified: '$HOSTNAME_ARG' is absent from the host list and from deleted hosts."
    exit 0
  fi
  sleep 2
done
die "verification failed: '$HOSTNAME_ARG' (${KEYS[*]}) still present in host list or deleted hosts"
