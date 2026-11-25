#!/usr/bin/env bash
# Put the eval hub into the state every mp-* case grades against. The cases
# share one hub, so the fixtures are set up together and must not disturb each
# other's expected answers.
#
# mp-01-health and mp-02-alert-sql: a healthy hub makes an empty answer
# correct, so hosts are put into three Health categories:
#
#   host001  cf-execd stopped, cf-serverd left up: the hub keeps collecting but
#            the agent never runs -> agentNotRunRecently (after ~10 minutes;
#            the threshold is GREATEST(600s, 1.3 x agent interval))
#
# The hub does not know the agent's schedule: agentexecutioninterval is learned
# from the gap between recorded runs. A client VM that sat powered off for days
# comes back with an interval of days, and would take a week to be flagged. So
# host001 runs a few times, a minute apart, with a collection after each, to
# teach the hub a short interval before cf-execd is stopped. The interval is a
# running average, not the last gap -- on the 3.27.1 eval hub it went
# 486433 -> 4059 -> 1275 -> 393 -> 130 -> 49 -> 26 seconds over nine cycles --
# so loop until it is under 460s, where the 600s floor takes over.
#   host002  deleted through the API while it keeps reporting
#            -> deletedHostsReport
#   host003  renamed to hub.example.com, so two identities report one name
#            -> hostsUsingSameName, for both it and the hub. This category is
#            the hard part: /api/health-diagnostic/report_ids omits it (3.27.1).
#            It has to pair with a live host -- a deleted host's name does not
#            count -- and not host001, or host001 leaves agentNotRunRecently
#            (a host is listed under one category only).
#
# mp-05-diagnose, T4: user alice has role web_team, whose excludeContext
# "windows|debian_12_14" hides host001 -- the only host on Debian 12.14 -- from
# her. The agent has to find which part of the expression matches.
#
# Keep the hub under its license. The free Enterprise license covers 25
# clients, and past that cf-hub stops collecting from *every* host -- the
# fixtures above then decay into "Unreachable hosts" and the preflight fails.
# That is what 1120 generator hosts for mp-03-all-hosts once did. mp-03 now
# needs a license past 1122 hosts and cleans up its clones itself; any it left
# behind (an interrupted run) are removed here.
#
# Idempotent: rerun it before an eval run. The grader re-derives the expected
# answer from the live hub and each case's preflight refuses to start on a hub
# missing its state, so a half-set-up hub cannot produce a misleading score.
#
#   MP_VAGRANT_DIR=~/.../vagrant/3.27/3.27.1 MP_URL=https://192.168.56.2 \
#     MP_USER=admin MP_PASSWORD=... ./setup-hub.sh
set -euo pipefail
: "${MP_VAGRANT_DIR:?set MP_VAGRANT_DIR to the vagrant project with hub, host001, host002}"
: "${MP_URL:?}" "${MP_USER:?}" "${MP_PASSWORD:?}"

# Credentials reach curl as a netrc on a file descriptor, not as -u: an
# argument shows in ps, and some calls here need stdin for a request body.
hub_host=${MP_URL#*://}; hub_host=${hub_host%%[:/]*}
# Resolved before the cd below: $0 may be a relative path.
here=$(cd "$(dirname "$0")" && pwd)
hcurl() {
  curl -sk --netrc-file <(printf 'machine %s login %s password %s\n' "$hub_host" "$MP_USER" "$MP_PASSWORD") "$@"
}

cd "$MP_VAGRANT_DIR"
H1_IP=${MP_HOST001_IP:-192.168.56.3}
vagrant ssh host001 -- "sudo systemctl stop cf-execd" 2>/dev/null
interval() {
  hcurl -X POST -H 'Content-Type: application/json' \
    -d "{\"query\":\"SELECT a.agentexecutioninterval FROM hosts h JOIN agentstatus a USING (hostkey) WHERE h.ipaddress = '$H1_IP'\"}" \
    "$MP_URL/api/query" | python3 -c 'import json,sys; r=json.load(sys.stdin)["data"][0]["rows"]; print(r[0][0] if r else 999999)'
}
for _ in $(seq 1 15); do
  i=$(interval)
  echo "setup-hub: host001 learned agent interval ${i}s"
  [ "$i" -lt 460 ] && break
  vagrant ssh host001 -- "sudo /var/cfengine/bin/cf-agent -K >/dev/null 2>&1" 2>/dev/null
  vagrant ssh hub -- "sudo /var/cfengine/bin/cf-hub -q delta -H $H1_IP >/dev/null 2>&1" 2>/dev/null
done

H2_IP=${MP_HOST002_IP:-192.168.56.4}
# Every live record at host002's IP, not just the first: a second one (a
# re-bootstrap, a re-key) would otherwise stay live and quietly break the
# "deleted but still reporting" fixture.
keys=$(hcurl "$MP_URL/api/host?count=1000" \
  | python3 -c 'import json,sys; ip=sys.argv[1]
print(" ".join(h["id"] for h in json.load(sys.stdin)["data"] if h.get("ip")==ip))' "$H2_IP") ||
  { echo "setup-hub: could not list hosts (API error)" >&2; exit 1; }
for key in $keys; do
  hcurl -X DELETE "$MP_URL/api/host/$key" -o /dev/null
  echo "setup-hub: deleted $key ($H2_IP)"
done
# host003: HOSTS=3 so the Vagrantfile defines it. The package is uploaded, not
# read from /vagrant: with Guest Additions 6.0 on VirtualBox 7.2 the shared
# folder handed dpkg a truncated .deb.
H3_IP=${MP_HOST003_IP:-192.168.56.5}
HOSTS=3 vagrant up host003 --no-provision >/dev/null
deb=$(ls packages/PACKAGES_x86_64_linux_debian_12/cfengine-nova_*.deb | tail -1)
vagrant upload "$deb" /tmp/nova.deb host003 >/dev/null
hub_ip=${MP_URL#*://}; hub_ip=${hub_ip%%[:/]*}
vagrant ssh host003 -- "
  [ -x /var/cfengine/bin/cf-agent ] || sudo DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/nova.deb >/dev/null
  [ -f /var/cfengine/policy_server.dat ] || sudo /var/cfengine/bin/cf-agent -B $hub_ip >/dev/null
  sudo hostnamectl set-hostname hub.example.com
  sudo sed -i 's/^127.0.1.1.*/127.0.1.1 hub.example.com hub/' /etc/hosts
  sudo /var/cfengine/bin/cf-agent -K >/dev/null 2>&1" 2>/dev/null
for _ in 1 2; do
  vagrant ssh hub -- "sudo /var/cfengine/bin/cf-hub -q rebase -H $H3_IP >/dev/null 2>&1" 2>/dev/null
done

# mp-05-diagnose T4. PUT creates or replaces (3.27.1); POST is the fallback
# for versions where PUT on an existing id fails.
# alice's password is random and discarded: nothing logs in as her.
role='{"description":"Web team: Linux web servers","includeContext":"linux","excludeContext":"windows|debian_12_14"}'
for m in PUT POST; do
  c=$(hcurl -o /dev/null -w '%{http_code}' -X $m \
        -H 'Content-Type: application/json' -d "$role" "$MP_URL/api/role/web_team")
  [ "${c:0:1}" = 2 ] && break
done
echo "setup-hub: role web_team ($c)"
pw=$(python3 -c 'import secrets; print(secrets.token_urlsafe(18) + "Aa1")')
c=$(printf '{"password":"%s","email":"alice@example.com","roles":["web_team"]}' "$pw" \
    | hcurl -o /dev/null -w '%{http_code}' -X PUT \
        -H 'Content-Type: application/json' -d @- "$MP_URL/api/user/alice")
unset pw
if [ "${c:0:1}" != 2 ]; then
  c=$(hcurl -o /dev/null -w '%{http_code}' -X POST \
        -H 'Content-Type: application/json' -d '{"roles":["web_team"]}' "$MP_URL/api/user/alice")
fi
echo "setup-hub: user alice ($c)"

PSQL="sudo -u cfpostgres /var/cfengine/bin/psql -d cfdb -qAt"
vagrant ssh hub -- "
  for t in __variables __contexts __agentstatus __lastseenhosts __inventory __hosts; do
    $PSQL -c \"DELETE FROM \$t WHERE hostkey LIKE 'SHA=evalpg%'\" 2>/dev/null
  done
  true" 2>/dev/null
bash "$here/mp-clone-hosts.sh" cleanup


hcurl "$MP_URL/api/health-diagnostic/status"; echo
