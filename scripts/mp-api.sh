#!/usr/bin/env bash
# Call the CFEngine Mission Portal REST API without the caller ever holding
# the password.
#
#   mp-api.sh GET  /api/health-diagnostic/status
#   mp-api.sh POST /api/query '{"query":"SELECT hostname FROM hosts"}'
#   mp-api.sh POST /api/query - < body.json
#   mp-api.sh --write DELETE /api/host/SHA=...   # changes the hub: say so
#   mp-api.sh --check          # one-line status, for the skill's load block
#
# The caller is usually an agent. Everything it runs and reads lands in a
# transcript, so the password must not pass through it: not in chat, not typed
# into a command (the transcript keeps it), not in output.
# Credentials therefore come from a netrc file, which curl reads itself, and
# this script only ever prints the login name.
#
# The login is the user's own, so the agent can do anything their role allows.
# Requests are read-only unless --write is given: GET, and POST to the
# endpoints that only read (query, inventory, health reports). Anything else
# -- deleting a host, changing settings, triggering an agent run -- is refused
# without it. This is a speed bump, not a security boundary: --write is one
# word away. It puts every change in the command line, where the user sees it
# and a permission rule can match it. The boundary is the user's role.
#
# Configuration, environment first, then the config file:
#
#   MP_URL       url=      https://hub.example.com                (required)
#   MP_NETRC     netrc=    netrc file (default ~/.netrc)
#   MP_CACERT    cacert=   the hub's certificate, for a self-signed hub
#   MP_INSECURE  insecure= 1 to skip certificate verification (lab hubs only)
#
# Config file: $MP_CONFIG, default ${XDG_CONFIG_HOME:-~/.config}/cfengine/mission-portal.conf,
# plain KEY=value lines. It is parsed, never sourced -- it sits beside a
# credentials file and should not be able to run code.
#
# Exit status: 0 on HTTP 2xx; 1 misconfigured, bad usage, or a write without
# --write; 2 HTTP error (the status and body go to stderr); 3 transport failure
# (DNS, TLS, refused).
set -uo pipefail

CONFIG=${MP_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/cfengine/mission-portal.conf}

conf() {  # conf <key> -> value from the config file, or empty
  [ -f "$CONFIG" ] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$CONFIG" | tail -1 | sed 's/[[:space:]]*$//'
}

URL=${MP_URL:-$(conf url)}
URL=${URL%/}
NETRC=${MP_NETRC:-$(conf netrc)}
NETRC=${NETRC:-$HOME/.netrc}
NETRC=${NETRC/#\~/$HOME}
CACERT=${MP_CACERT:-$(conf cacert)}
CACERT=${CACERT/#\~/$HOME}
INSECURE=${MP_INSECURE:-$(conf insecure)}

host_of() { local h=${1#*://}; h=${h%%/*}; echo "${h%%:*}"; }

netrc_login() {  # netrc_login <host> -> login for that machine, or default
  [ -r "$NETRC" ] || return 0
  # netrc is whitespace-separated tokens, not lines; entries may span lines.
  tr -s ' \t\n' '\n' < "$NETRC" | awk -v host="$1" '
    $0 == "machine" { getline m; cur = (m == host); next }
    $0 == "default" { cur = 2; next }
    $0 == "login" && cur { getline l; if (cur == 1) { print l; found = 1; exit } else if (!dflt) dflt = l }
    END { if (!found && dflt) print dflt }'
}

problem() {  # everything a user needs to fix the setup, never the password
  local host
  host=$(host_of "${URL:-https://hub.example.com}")
  cat <<EOF
Mission Portal API is not configured: $1
Set it up once (the agent never needs to see the password):
  mkdir -p ${CONFIG%/*}
  echo 'url=https://$host' > $CONFIG
  echo 'machine $host login <your-login> password <password>' >> ~/.netrc
  chmod 600 ~/.netrc
Use your own Mission Portal login; the agent acts with your role's permissions.
EOF
}

curl_tls_args() {
  if [ "$INSECURE" = 1 ]; then
    echo "-k"
  elif [ -n "$CACERT" ]; then
    printf -- '--cacert\n%s\n' "$CACERT"
  fi
}

request() {  # request <method> <path> [body] -> sets STATUS, BODY_FILE, RC
  local method=$1 path=$2 body=${3-}
  local -a tls args
  mapfile -t tls < <(curl_tls_args)
  # No "Accept: application/json": Mission Portal answers any Accept that names
  # it with 406 "Unsupported format or version requested" (3.27.1). curl's
  # default */* works.
  args=(-sS -X "$method" --netrc-file "$NETRC"
        -o "$BODY_FILE" -w '%{http_code}' --connect-timeout 10 --max-time 300)
  [ -n "$body" ] && args+=(-H "Content-Type: application/json" --data-binary "$body")
  # ${tls[@]+...}: tls is empty in the recommended setup (neither insecure=
  # nor cacert=), and "${tls[@]}" on an empty array is an unbound-variable
  # error under set -u before bash 4.4 (RHEL 7 ships 4.2).
  STATUS=$(curl ${tls[@]+"${tls[@]}"} "${args[@]}" "$URL$path" 2>"$ERR_FILE"); RC=$?
}

BODY_FILE=$(mktemp); ERR_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE" "$ERR_FILE"' EXIT

if [ "${1-}" = --check ]; then
  # Runs at skill load: always exit 0, one short paragraph at most.
  [ -n "$URL" ] || { problem "no hub URL (MP_URL or url= in $CONFIG)"; exit 0; }
  host=$(host_of "$URL")
  login=$(netrc_login "$host")
  [ -n "$login" ] || { problem "no entry for $host in $NETRC"; exit 0; }
  request GET /api/
  if [ "$RC" = 60 ] || grep -qi "certificate" "$ERR_FILE"; then
    cat <<EOF
Mission Portal: $URL as $login -- certificate not trusted.
The hub's certificate is probably self-signed. Save it and set cacert= in $CONFIG:
  openssl s_client -connect $host:443 </dev/null 2>/dev/null | openssl x509 > ${CONFIG%/*}/hub.pem
Compare its fingerprint (openssl x509 -noout -fingerprint -sha256 -in ${CONFIG%/*}/hub.pem)
with the hub's own certificate under /var/cfengine/httpd/ssl/certs/ before trusting it.
EOF
  elif [ "$RC" != 0 ]; then
    echo "Mission Portal: $URL as $login -- unreachable: $(head -1 "$ERR_FILE")"
  elif [ "$STATUS" = 401 ]; then
    echo "Mission Portal: $URL as $login -- login rejected (HTTP 401). Check the password in $NETRC."
  elif [ "${STATUS:0:1}" != 2 ]; then
    echo "Mission Portal: $URL as $login -- HTTP $STATUS from /api/"
  else
    version=$(python3 -c 'import json,sys; d=json.load(sys.stdin)["data"][0]; print(d.get("enterpriseVersion") or d.get("coreVersion") or "?")' \
              < "$BODY_FILE" 2>/dev/null || echo "?")
    echo "Mission Portal: $URL as $login (CFEngine Enterprise $version). Call it with mp-api.sh."
  fi
  exit 0
fi

write=0
[ "${1-}" = --write ] && { write=1; shift; }
if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  sed -n '5,10p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 1
fi
method=$(echo "$1" | tr '[:lower:]' '[:upper:]'); path=$2; body=${3-}
case "$path" in /*) ;; *) echo "mp-api: path must start with /, e.g. /api/host" >&2; exit 1 ;; esac

reads_only() {  # reads_only <method> <path>: true if the request cannot change the hub
  case "$1" in GET|HEAD) return 0 ;; POST) ;; *) return 1 ;; esac
  case "${2%%\?*}" in
    /api/query|/api/query/async|/api/inventory) return 0 ;;
    /api/health-diagnostic/report/*) return 0 ;;
  esac
  return 1
}
if [ "$write" = 0 ] && ! reads_only "$method" "$path"; then
  cat >&2 <<EOF
mp-api: refused: $method $path can change the hub.
Get the user's go-ahead for this specific change, then rerun with --write:
  mp-api.sh --write $method $path ...
EOF
  exit 1
fi
[ "$body" = - ] && body=$(cat)
[ -n "$URL" ] || { problem "no hub URL (MP_URL or url= in $CONFIG)" >&2; exit 1; }
[ -n "$(netrc_login "$(host_of "$URL")")" ] || { problem "no entry for $(host_of "$URL") in $NETRC" >&2; exit 1; }

request "$method" "$path" "$body"
if [ "$RC" != 0 ]; then
  echo "mp-api: $(head -1 "$ERR_FILE")" >&2
  exit 3
fi
if [ "${STATUS:0:1}" != 2 ]; then
  echo "mp-api: HTTP $STATUS from $method $path" >&2
  head -c 2000 "$BODY_FILE" >&2; echo >&2
  exit 2
fi
cat "$BODY_FILE"
