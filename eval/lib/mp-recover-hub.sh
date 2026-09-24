#!/usr/bin/env bash
# Put the eval hub's real hosts back after a run that damaged them.
#
# mp-06-remove-host hands a model a delete-capable login, and a careless
# script can remove more than its target: on 2026-09-23 a no-skill agent
# deleted every real host, and another tried to purge all deleted ones. The
# fixtures are machines that keep running, so they can always be brought
# back; this does it instead of a person.
#
#   hub      192.168.56.2   live
#   host001  192.168.56.3   live (agent stopped by mp-setup-hub.sh)
#   host002  192.168.56.4   deleted, and still reporting
#   host003  192.168.56.5   live (renamed hub.example.com)
#   host004  192.168.56.6   live (re-keyed by mp-rekey-host.sh)
#
# What the hub does, and so what this does (3.27.1):
# - A deleted host's reporting data goes at once and its trusted key within
#   minutes, so undelete (POST /api/hosts/restore-deleted/:key) alone does not
#   bring it back: the record returns empty and the host cannot connect. Undelete,
#   re-bootstrap the client, collect. If the record still has no hostname,
#   purge it, re-bootstrap, collect -- the host registers again, same key.
# - host002 must stay deleted. If it was purged, bootstrap it and delete it again.
#   If its reports are stale, restart its cf-serverd: it wedged on 2026-09-23
#   with the hub's connections in CLOSE-WAIT and stalled collection.
# - Leftover synthetic hosts are removed (mp-synthetic-hosts.sh cleanup).
# If anything was repaired, mp-setup-hub.sh and mp-rekey-host.sh run after, to
# rebuild the fixtures on top (host001's agent interval, host004's old record).
#
# The harness runs this after every mp-06 invocation (case "post_run"); run it by hand
# when a preflight fails after anything that deletes hosts.
#
#   MP_VAGRANT_DIR=... MP_URL=... MP_USER=admin MP_PASSWORD=... mp-recover-hub.sh
set -uo pipefail
: "${MP_VAGRANT_DIR:?}" "${MP_URL:?}" "${MP_USER:?}" "${MP_PASSWORD:?}"
here=$(cd "$(dirname "$0")" && pwd)
hub_ip=${MP_URL#*://}; hub_ip=${hub_ip%%[:/]*}

declare -A VM=([192.168.56.2]=hub [192.168.56.3]=host001 [192.168.56.5]=host003 [192.168.56.6]=host004)
DELETED_IP=192.168.56.4 DELETED_VM=host002
repaired=0

api() {  # api <METHOD> <path> [body] -> body; HTTP code in $CODE
  local out
  out=$(printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
    curl -sk -m 60 -K - -X "$1" ${3:+-H 'Content-Type: application/json' --data-binary "$3"} \
      -w '\n%{http_code}' "$MP_URL$2")
  CODE=${out##*$'\n'}; printf '%s' "${out%$'\n'*}"
}
vm() { (cd "$MP_VAGRANT_DIR" && HOSTS=4 vagrant ssh "$1" -- "$2" 2>/dev/null); }
collect() { vm hub "sudo /var/cfengine/bin/cf-hub -q rebase -H $1 >/dev/null 2>&1"; }
bootstrap() { vm "$1" "sudo /var/cfengine/bin/cf-agent -B $hub_ip >/dev/null 2>&1"; }


# Lookups set a global and return non-zero on an API error or non-JSON. They
# run in this shell, not in $(...), so a caller's `|| die` really stops the
# script: a transient error must never read as "host002 is not deleted"
# (which would bootstrap it live) or as "this host is gone" (which would
# start repairing a healthy one).
die() { echo "mp-recover-hub: $*" >&2; exit 2; }
q() {  # q <sql> -> rows as "col1 col2 ..." lines, or return 1
  api POST /api/query "$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$1")" |
    python3 -c 'import json,sys; [print(*r) for r in json.load(sys.stdin)["data"][0]["rows"]]' 2>/dev/null
}
fetch_live() {  # fetch_live <ip> -> LIVE: "hostkey hostname" lines
  LIVE=$(q "SELECT hostkey, coalesce(hostname, '-') FROM hosts WHERE ipaddress = '$1'")
}
fetch_deleted() {  # fetch_deleted <ip> -> DELETED: hostkeys
  DELETED=$(api GET "/api/hosts/deleted?limit=10000" |
    python3 -c 'import json,sys; [print(h["hostkey"]) for h in json.load(sys.stdin)["data"] if h.get("ipaddress")==sys.argv[1]]' "$1" 2>/dev/null)
}
# A machine is back when a record at its IP has a hostname and reported
# recently -- not merely when some record there is live: host004 keeps a
# leftover record from its re-key (mp-07's fixture) at the same IP, and that
# alone once made a deleted host004 look intact. 0 live, 1 not, 2 API error.
named_live() {
  local n
  n=$(q "SELECT count(*) FROM hosts WHERE ipaddress = '$1' AND hostname IS NOT NULL AND lastreporttimestamp > now() - interval '20 minutes'") || return 2
  [ "${n:-0}" -gt 0 ]
}
check_live() {  # check_live <ip>: 0 live, 1 not live; dies on an API error
  named_live "$1"; local rc=$?
  [ $rc -eq 2 ] && die "could not check $1 (API error)"
  return $rc
}
# The hostname arrives with inventory, a collection or two after a bootstrap:
# check a few times, collecting again in between, before calling it missing.
settled_live() {  # settled_live <ip>
  local _
  for _ in 1 2 3 4; do
    check_live "$1" && return 0
    sleep 15; collect "$1"
  done
  check_live "$1"
}

# Stop before touching anything if the API itself is not answering.
q "SELECT 1" >/dev/null || die "the Mission Portal API is not answering at $MP_URL (or the login is wrong); nothing changed"

for ip in "${!VM[@]}"; do
  check_live "$ip" && continue
  name=${VM[$ip]}
  echo "mp-recover-hub: $name ($ip) is not live -- repairing"
  repaired=1
  # Only the records deleted now. Another record at the same IP -- host004's
  # leftover from its re-key, mp-07's fixture -- is left alone throughout.
  fetch_deleted "$ip" || die "could not list deleted hosts (API error)"
  restored=$DELETED
  for k in $restored; do api POST "/api/hosts/restore-deleted/$k" >/dev/null; done
  bootstrap "$name"; collect "$ip"
  settled_live "$ip" && { echo "mp-recover-hub: $name back after undelete"; continue; }
  # Undelete brought back an empty record: purge that record and register again.
  for k in $restored; do api DELETE "/api/host/$k" >/dev/null; done
  for k in $restored; do
    for _ in $(seq 1 20); do
      fetch_deleted "$ip" || die "could not list deleted hosts (API error)"
      grep -qxF "$k" <<< "$DELETED" && break; sleep 1
    done
    api DELETE "/api/hosts/delete-permanently/$k" >/dev/null
  done
  bootstrap "$name"; collect "$ip"
  if settled_live "$ip"; then echo "mp-recover-hub: $name back after purge and re-bootstrap"
  else echo "mp-recover-hub: $name ($ip) is still not live" >&2; fi
done

# host002: deleted, and still reporting.
fetch_deleted "$DELETED_IP" || die "could not list deleted hosts (API error)"
if [ -z "$DELETED" ]; then
  echo "mp-recover-hub: $DELETED_VM ($DELETED_IP) is not a deleted host -- repairing"
  repaired=1
  fetch_live "$DELETED_IP" || die "could not list live hosts (API error)"
  if [ -z "$LIVE" ]; then
    bootstrap "$DELETED_VM"; collect "$DELETED_IP"
    fetch_live "$DELETED_IP" || die "could not list live hosts (API error)"
  fi
  for k in $(awk '{print $1}' <<< "$LIVE"); do api DELETE "/api/host/$k" >/dev/null; done
  for _ in $(seq 1 20); do
    fetch_deleted "$DELETED_IP" || die "could not list deleted hosts (API error)"
    [ -n "$DELETED" ] && break; sleep 1
  done
fi
stale=$(api POST /api/health-diagnostic/report/deletedHostsReport '{"limit": 10000}' |
  python3 -c 'import json,sys,datetime as d
t=json.load(sys.stdin)["data"][0]; c=[h["columnName"] for h in t["header"]]
r=[x for x in t["rows"] if x[c.index("ipaddress")]==sys.argv[1]]
if not r: print("missing"); sys.exit()
ts=d.datetime.fromisoformat(r[0][c.index("Last report attempt")].replace("+00","+00:00").split(".")[0]+"+00:00")
print("stale" if (d.datetime.now(d.timezone.utc)-ts).total_seconds() > 900 else "ok")' "$DELETED_IP" 2>/dev/null) ||
  die "could not read the deleted-hosts report (API error)"
if [ "$stale" != ok ]; then
  echo "mp-recover-hub: $DELETED_VM's reports are ${stale:-unknown} -- restarting its cf-serverd"
  vm "$DELETED_VM" "sudo systemctl restart cf-serverd"
fi

bash "$here/mp-synthetic-hosts.sh" cleanup || die "synthetic host cleanup failed"

# The invariant the other cases grade against: host002 deleted, nothing live at its IP.
fetch_deleted "$DELETED_IP" || die "could not list deleted hosts (API error)"
[ -n "$DELETED" ] || die "$DELETED_VM is not in the deleted list after repair"
fetch_live "$DELETED_IP" || die "could not list live hosts (API error)"
[ -z "$LIVE" ] || die "$DELETED_VM still has a live record after repair"

if [ "$repaired" = 1 ]; then
  echo "mp-recover-hub: rebuilding fixtures"
  bash "$here/mp-setup-hub.sh" | tail -1
  bash "$here/mp-rekey-host.sh"
else
  echo "mp-recover-hub: real hosts intact"
fi
