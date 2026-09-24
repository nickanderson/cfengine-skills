#!/usr/bin/env bash
# mp-07-reinstalled: a machine reinstalled with a new identity, leaving its old
# record behind.
#
# host004 (192.168.56.6, HOSTS=4 in the Vagrantfile) is bootstrapped, collected,
# then given a new keypair and bootstrapped again. Mission Portal keeps both
# records under host004.example.com at the same IP. The old one never reports
# again, and after blueHostHorizon (40 minutes on the eval hub) it shows under
# "Unreachable hosts" -- and still in the "Duplicate hostnames" report list,
# though /status stops counting it there (3.27.1). hub.example.com, two live
# machines sharing a name (mp-01), is the decoy: same name is not a reinstall.
#
# Idempotent: does nothing if host004 already has a leftover record. After a
# fresh re-key, wait out the horizon before running mp-07; its preflight
# refuses until the old record is stale.
#
#   MP_VAGRANT_DIR=... MP_URL=... MP_USER=admin MP_PASSWORD=... mp-rekey-host.sh
set -euo pipefail
: "${MP_VAGRANT_DIR:?}" "${MP_URL:?}" "${MP_USER:?}" "${MP_PASSWORD:?}"
IP=${MP_HOST004_IP:-192.168.56.6}
hub_ip=${MP_URL#*://}; hub_ip=${hub_ip%%[:/]*}
cd "$MP_VAGRANT_DIR"

records() {
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
    curl -sk -K - "$MP_URL/api/host?count=1000" |
    python3 -c 'import json,sys; print(sum(1 for h in json.load(sys.stdin)["data"] if h.get("ip")==sys.argv[1]))' "$IP"
}
collect() { vagrant ssh hub -- "sudo /var/cfengine/bin/cf-hub -q rebase -H $IP >/dev/null 2>&1" 2>/dev/null; }

n=$(records)
if [ "$n" -ge 2 ]; then echo "mp-rekey-host: $IP already has $n records"; exit 0; fi

HOSTS=4 vagrant up host004 --no-provision >/dev/null
if [ "$n" -eq 0 ]; then
  deb=$(ls packages/PACKAGES_x86_64_linux_debian_12/cfengine-nova_*.deb | tail -1)
  HOSTS=4 vagrant upload "$deb" /tmp/nova.deb host004 >/dev/null
  HOSTS=4 vagrant ssh host004 -- "
    [ -x /var/cfengine/bin/cf-agent ] || sudo DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/nova.deb >/dev/null
    sudo /var/cfengine/bin/cf-agent -B $hub_ip >/dev/null 2>&1
    sudo /var/cfengine/bin/cf-agent -K >/dev/null 2>&1" 2>/dev/null
  collect
fi
# The reinstall: a new keypair, bootstrapped again.
HOSTS=4 vagrant ssh host004 -- "
  sudo systemctl stop cfengine3
  sudo rm -f /var/cfengine/ppkeys/localhost.priv /var/cfengine/ppkeys/localhost.pub
  sudo /var/cfengine/bin/cf-key >/dev/null 2>&1
  sudo /var/cfengine/bin/cf-agent -B $hub_ip >/dev/null 2>&1
  sudo /var/cfengine/bin/cf-agent -K >/dev/null 2>&1" 2>/dev/null
collect
echo "mp-rekey-host: $IP now has $(records) records; the old one is stale after blueHostHorizon"
