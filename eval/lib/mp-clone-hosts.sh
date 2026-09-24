#!/usr/bin/env bash
# A fleet of synthetic hosts cloned from a real one, for cases that need more
# hosts than the vagrant env runs (mp-03-all-hosts).
#
#   mp-clone-hosts.sh create <count> [template-fqhost]   replace any old clones
#   mp-clone-hosts.sh tick                               make them look current
#   mp-clone-hosts.sh cleanup                            remove every clone
#   mp-clone-hosts.sh status                             count clones, and health
#
# Mission Portal's own data generator writes values no host would report (MD5
# hashes for product names, ubuntu hosts in debian_jessie, CFEngine 3.14 on a
# 3.27 hub, a "New " copy of every variable), and a model looking at it can
# tell it is fake. A clone is instead the template's real reporting rows with
# every identity in them (hostkey, names, IP, MACs, UUID and the classes built
# from them) replaced consistently. See mp-clone-hosts.sql.
#
# Clones live in 172.16.0.0/12, which create excludes from cf-hub's
# collection (def.control_hub_exclude_hosts, set in the hub's
# /var/cfengine/data/host_specific.json and tagged noreport so it stays out of
# cfdb). Without that cf-hub tries to collect from 1118 unreachable addresses
# and its batch stalls, taking every real host to "Unreachable".
#
# Clones are rows in cfdb that cf-hub never collects, so after 40 minutes
# Mission Portal counts them as "Unreachable hosts". create leaves them fresh;
# tick moves each clone's last report and last agent run forward the way a
# healthy host on a 5-minute schedule would. Run it before any case that looks
# at freshness or Health.
#
# Clone n is SHA=sha256("mp-clone:<n>"). The hub keeps only the count, in
# /var/lib/mp-eval-clones/count, so nothing in cfdb marks a host as a clone.
#
# Every clone counts against the hub's license, and past it cf-hub stops
# collecting from every host (see mp-setup-hub.sh); create refuses to exceed
# the licensed count.
#
# Needs MP_VAGRANT_DIR (the hub's vagrant project). The harness keeps it out of
# the model's environment.
set -euo pipefail
: "${MP_VAGRANT_DIR:?}"
here=$(cd "$(dirname "$0")" && pwd)
state=/var/lib/mp-eval-clones
psql="sudo /var/cfengine/bin/psql cfdb -qAt -v ON_ERROR_STOP=1"

# stderr passes through, less vagrant's "Connection to ... closed." noise: a
# failed psql is otherwise silent, since set -e exits without saying why.
hub() { (cd "$MP_VAGRANT_DIR" && vagrant ssh hub -- "$@" 2> >(grep -v '^Connection to .* closed' >&2)); }

clone_count() { hub "sudo cat $state/count 2>/dev/null || echo 0"; }

keys_sql() {  # keys_sql <count> -> SQL listing the clone hostkeys as column k
  echo "SELECT 'SHA=' || encode(sha256(convert_to('mp-clone:' || n, 'UTF8')), 'hex') AS k
        FROM generate_series(1, $1) n"
}

tick() {
  hub "$psql" <<EOF
SET client_min_messages = warning;
CREATE TEMP TABLE k AS $(keys_sql "$(clone_count)");
UPDATE __hosts h SET lastreporttimestamp = now() - random() * interval '240 seconds'
  FROM k WHERE h.hostkey = k.k AND h.deleted IS NULL;
UPDATE __agentstatus a SET lastagentlocalexecutiontimestamp = h.lastreporttimestamp - (20 + random() * 200) * interval '1 second'
  FROM __hosts h, k WHERE a.hostkey = h.hostkey AND h.hostkey = k.k AND h.deleted IS NULL;
UPDATE __lastseenhosts l SET lastseentimestamp = h.lastreporttimestamp
  FROM __hosts h, k WHERE l.hostkey = h.hostkey AND h.hostkey = k.k AND h.deleted IS NULL;
EOF
}

cleanup() {
  local n t sql
  n=$(clone_count)
  sql="SET client_min_messages = warning; BEGIN; CREATE TEMP TABLE k AS $(keys_sql "$n");"
  for t in __variables __contexts contextcache __inventory __agentstatus __lastseenhosts __software \
           __softwareupdates __promiseexecutions __health_diagnostics_failures \
           __health_diagnostics_dismissed __hosts; do
    sql+=" DELETE FROM $t WHERE hostkey IN (SELECT k FROM k);"
  done
  printf '%s COMMIT;\n' "$sql" | hub "$psql"
  hub "sudo rm -f $state/count"
}

# Must match the clone IPs in mp-clone-hosts.sql.
exclude=172.16.0.0/12
augments=/var/cfengine/data/host_specific.json

ensure_excluded() {
  local want have
  want=$(printf '{\n  "variables": {\n    "default:def.control_hub_exclude_hosts": {\n      "value": [ "%s" ],\n      "tags": [ "noreport" ]\n    }\n  }\n}' "$exclude")
  have=$(hub "sudo cat $augments 2>/dev/null || true")
  [ "$have" = "$want" ] && return 0
  if [ -n "$have" ]; then
    echo "mp-clone-hosts: $augments on the hub has other content; add def.control_hub_exclude_hosts => $exclude to it by hand" >&2
    exit 1
  fi
  printf '%s\n' "$want" | hub "sudo install -m 600 /dev/stdin $augments && sudo systemctl restart cf-hub"
  hub "sudo /var/cfengine/bin/cf-promises --show-vars=control_hub_exclude_hosts" | grep -qF "$exclude" ||
    { echo "mp-clone-hosts: cf-promises does not see the exclusion" >&2; exit 1; }
  echo "mp-clone-hosts: excluded $exclude from collection, cf-hub restarted"
}

licensed() {  # the hub's licensed host count
  hub "sudo /var/cfengine/bin/cf-hub --show-license" | sed -n 's|^Utilization: *[0-9]*/\([0-9]*\).*|\1|p'
}

create() {
  local count=${1:?count} template=${2:-host001.example.com} lic real
  cleanup
  ensure_excluded
  lic=$(licensed)
  real=$(hub "$psql -c 'SELECT count(*) FROM __hosts'")
  if [ $((real + count)) -gt "${lic:-25}" ]; then
    echo "mp-clone-hosts: $real hosts + $count clones exceeds the ${lic:-25}-host license" >&2; exit 1
  fi
  # Recorded first, so cleanup finds whatever a failed create left behind.
  hub "sudo install -d -m 700 $state && echo $count | sudo tee $state/count >/dev/null"
  hub "$psql -v count=$count -v template=$template" < "$here/mp-clone-hosts.sql"
  status
}

status() {
  hub "$psql" <<EOF
CREATE TEMP TABLE k AS $(keys_sql "$(clone_count)");
SELECT 'clones: ' || count(*) || ', oldest report ' || coalesce(date_trunc('second', now() - min(lastreporttimestamp))::text, '-') || ' ago'
  FROM __hosts WHERE hostkey IN (SELECT k FROM k);
SELECT 'health ' || category || ': ' || count(*)
  FROM __health_diagnostics_failures WHERE hostkey IN (SELECT k FROM k) GROUP BY category;
EOF
}

case "${1-}" in
  create) shift; create "$@" ;;
  tick) tick ;;
  cleanup) cleanup ;;
  status) status ;;
  *) echo "usage: $0 create <count> [template-fqhost] | tick | cleanup | status" >&2; exit 2 ;;
esac
