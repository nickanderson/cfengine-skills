#!/usr/bin/env bash
# Synthetic hosts for mp-06-remove-host, which asks for a script that removes
# a host from Mission Portal for good. Every run destroys its target, so the
# harness recreates both hosts before each model invocation (case "pre_run")
# and the grader recreates them again before running the model's script.
#
#   decomm01.example.com     192.0.2.61  the host to remove
#   lab-decomm01.example.com 192.0.2.62  a decoy: a substring,
#                                        grep or LIKE match on
#                                        the name finds it too
#
#   mp-synthetic-hosts.sh create    remove any old ones, then make both
#   mp-synthetic-hosts.sh cleanup   remove both (live or deleted)
#
# Created with Mission Portal's own data generator, then renamed. Removed
# through the API's two-step delete, so nothing edits the base tables by hand
# except the rename. Two hosts: the free license covers 25 clients, and going
# past it stops collection from every host (see mp-setup-hub.sh).
#
# Needs MP_VAGRANT_DIR (the hub's vagrant project), MP_URL, MP_USER,
# MP_PASSWORD. The harness keeps MP_VAGRANT_DIR out of the model's environment.
set -euo pipefail
: "${MP_VAGRANT_DIR:?}" "${MP_URL:?}" "${MP_USER:?}" "${MP_PASSWORD:?}"

api() {  # api <method> <path> -> body on stdout, "HTTP <code>" on stderr
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
    curl -sk -K - -X "$1" -w '\n%{http_code}' "$MP_URL$2" |
    python3 -c 'import sys; *b, c = sys.stdin.read().split("\n"); print("\n".join(b)); print("HTTP", c, file=sys.stderr)'
}

keys_like() {  # keys_like <live|deleted> -> SHA=evaldel* keys
  if [ "$1" = live ]; then
    # Through the hosts view, not /api/host: a record with no inventory row
    # has no hostname, /api/host leaves it out, and cleanup used to miss it.
    # Leftovers piled up at IP 0.0.0.1, and cf-hub's collection batch stalled
    # ("Previous report collection batch still running") until they were gone.
    printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
      curl -sk -K - -X POST -H 'Content-Type: application/json' "$MP_URL/api/query" \
        -d '{"query": "SELECT hostkey FROM hosts WHERE hostkey LIKE '"'"'SHA=evaldel%'"'"'"}' |
      python3 -c 'import json,sys; print("\n".join(r[0] for r in json.load(sys.stdin)["data"][0]["rows"]))'  2>/dev/null
  else
    api GET "/api/hosts/deleted?limit=1000" 2>/dev/null | python3 -c 'import json,sys
print("\n".join(h["hostkey"] for h in json.load(sys.stdin)["data"] if h["hostkey"].startswith("SHA=evaldel")))'
  fi
}

# A failed lookup (a 500, non-JSON, an auth error) must not read as "none
# left": keys_like fails when its JSON does not parse, and every caller
# checks. Inside $(...) in a for list, set -e would not notice.
keys() {  # keys <live|deleted> -> keys, or exit 1
  keys_like "$1" || { echo "mp-synthetic-hosts: could not list $1 hosts (API error)" >&2; exit 1; }
}

cleanup() {
  local live deleted left_live left_deleted
  live=$(keys live)
  for k in $live; do api DELETE "/api/host/$k" >/dev/null 2>&1; done
  for _ in $(seq 1 20); do live=$(keys live); [ -z "$live" ] && break; sleep 1; done
  deleted=$(keys deleted)
  for k in $deleted; do api DELETE "/api/hosts/delete-permanently/$k" >/dev/null 2>&1; done
  left_live=$(keys live); left_deleted=$(keys deleted)
  [ -z "$left_live$left_deleted" ] ||
    { echo "mp-synthetic-hosts: could not remove: $left_live $left_deleted" >&2; exit 1; }
}

state() {  # hostnames of the live synthetic hosts, sorted
  api GET "/api/host?count=1000" 2>/dev/null | python3 -c 'import json,sys
print(" ".join(sorted(h.get("hostname") or "?" for h in json.load(sys.stdin)["data"] if h["id"].startswith("SHA=evaldel"))))'
}

WANT="decomm01.example.com lab-decomm01.example.com"

create() {
  # Fresh hostkeys every time: a regular delete is finished asynchronously by
  # the hub, by hostkey, so reusing the previous pair's keys let that late
  # cleanup remove one of the new hosts (2026-09-23: one host of two, a
  # different one on each attempt). Wait, and rebuild if needed.
  local attempt have
  for attempt in 1 2 3; do
    create_once
    for _ in $(seq 1 20); do
      have=$(state)
      [ "$have" = "$WANT" ] && { echo "mp-synthetic-hosts: $have"; return 0; }
      sleep 1
    done
    echo "mp-synthetic-hosts: attempt $attempt got: $have" >&2
  done
  echo "mp-synthetic-hosts: unexpected state after create: $have" >&2
  exit 1
}

create_once() {
  cleanup
  local prefix
  prefix="SHA=evaldel$(date +%s)x"
  local gen="sudo /var/cfengine/httpd/php/bin/php /var/cfengine/httpd/htdocs/public/index.php data_generator/HostsGenerator generate"
  local psql="sudo /var/cfengine/bin/psql cfdb -qAt"
  ( cd "$MP_VAGRANT_DIR" && vagrant ssh hub -- "
      $gen --hostKey=$prefix --hostCount=2 >/dev/null 2>&1
      rename() {
        $psql -c \"UPDATE __hosts SET hostname = '\$2', ipaddress = '\$3' WHERE hostkey = '\$1'\"
        $psql -c \"UPDATE __inventory SET values = values || jsonb_build_object('Host name', '\$2', 'IPv4 addresses', '\$3') WHERE hostkey = '\$1'\"
        $psql -c \"UPDATE __variables SET variablevalue = '\$2' WHERE hostkey = '\$1' AND variablename = 'fqhost'\"
      }
      rename ${prefix}1 decomm01.example.com 192.0.2.61
      rename ${prefix}2 lab-decomm01.example.com 192.0.2.62" 2>/dev/null )
}

case "${1-}" in
  create) create ;;
  cleanup) cleanup ;;
  *) echo "usage: $0 create|cleanup" >&2; exit 2 ;;
esac
