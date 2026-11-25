#!/bin/bash
# Re-runs the Mission Portal API queries used to build diagnosis.json.
# Needs MP_URL, MP_USER, MP_PASSWORD. -k because the hub cert is self-signed.
A=(-sk -u "$MP_USER:$MP_PASSWORD")
q() { curl "${A[@]}" -X POST -H 'Content-Type: application/json' "$MP_URL/api/query" -d "{\"query\":\"$1\"}"; echo; }

echo "### Health diagnostics summary"
curl "${A[@]}" "$MP_URL/api/health-diagnostic/status"; echo
for r in deletedHostsReport hostsNeverCollected notRecentlyCollected hostsUsingSameName hostsUsingSameIdentity agentNotRunRecently lastAgentRunUnsuccessful; do
  echo "### Health report: $r"
  curl "${A[@]}" -X POST -H 'Content-Type: application/json' "$MP_URL/api/health-diagnostic/report/$r" -d '{}'; echo
done

echo "### Hosts"
q "SELECT hostkey,hostname,ipaddress,lastreporttimestamp,firstreporttimestamp,hostkeycollisions FROM hosts"
echo "### Agent status"
q "SELECT * FROM agentstatus"
echo "### Hostname variables"
q "SELECT hostkey,variablename,variablevalue FROM variables WHERE variablename IN ('fqhost','uqhost')"
echo "### Hub lastseen (incoming connections from hosts)"
q "SELECT remotehostkey,remotehostip,lastseendirection,lastseentimestamp FROM lastseenhosts WHERE hostkey='SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940'"

echo "### RBAC: alice and her role"
curl "${A[@]}" "$MP_URL/api/user/alice"; echo
curl "${A[@]}" "$MP_URL/api/role/web_team"; echo
q "SELECT hostkey,contextname FROM contexts WHERE contextname IN ('linux','windows','debian_12_14')"
