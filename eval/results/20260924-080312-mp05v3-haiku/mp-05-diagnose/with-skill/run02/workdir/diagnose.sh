#!/usr/bin/env bash
set -euo pipefail

# Helper function to make API calls
api_call() {
  /tmp/cfeval-mp-05-diagnose-with-skill.NXxP72ES/config/skills/mission-portal/../scripts/mp-api.sh "$@"
}

# Get all hosts with detailed information
echo "=== Fetching all hosts ===" >&2
all_hosts=$(api_call POST /api/query '{"query": "SELECT hostkey, hostname, ipaddress, lastreporttimestamp, firstreporttimestamp FROM hosts"}')
echo "$all_hosts" | jq '.data[0].rows' > /tmp/hosts_list.json

# Get agent status
echo "=== Fetching agent status ===" >&2
agent_status=$(api_call POST /api/query '{"query": "SELECT hostkey, lastagentlocalexecutiontimestamp, lastagentexecutionstatus, agentexecutioninterval FROM agentstatus"}')
echo "$agent_status" | jq '.data[0].rows' > /tmp/agent_status.json

# Get all contexts (classes) for all hosts - get count per hostkey
echo "=== Fetching host contexts ===" >&2
contexts=$(api_call POST /api/query '{"query": "SELECT hostkey, context FROM contexts"}')
echo "$contexts" | jq '.data[0].rows' > /tmp/contexts.json

# Get health diagnostic status
echo "=== Fetching health diagnostic status ===" >&2
health_status=$(api_call GET /api/health-diagnostic/status)
echo "$health_status" | jq '.' > /tmp/health_status.json

# Get deleted hosts report
echo "=== Fetching deleted hosts ===" >&2
deleted_hosts=$(api_call POST /api/health-diagnostic/report/deletedHostsReport '{"limit": 10000}')
echo "$deleted_hosts" | jq '.data' > /tmp/deleted_hosts.json

# Get unreachable hosts
echo "=== Fetching unreachable hosts ===" >&2
unreachable=$(api_call POST /api/health-diagnostic/report/notRecentlyCollected '{"limit": 10000}')
echo "$unreachable" | jq '.data' > /tmp/unreachable_hosts.json

# Get hosts never collected
echo "=== Fetching hosts never collected ===" >&2
never_collected=$(api_call POST /api/health-diagnostic/report/hostsNeverCollected '{"limit": 10000}')
echo "$never_collected" | jq '.data' > /tmp/never_collected.json

# Get duplicate identities
echo "=== Fetching duplicate identities ===" >&2
dup_identities=$(api_call POST /api/health-diagnostic/report/hostsUsingSameIdentity '{"limit": 10000}')
echo "$dup_identities" | jq '.data' > /tmp/dup_identities.json

# Get duplicate hostnames
echo "=== Fetching duplicate hostnames ===" >&2
dup_hostnames=$(api_call POST /api/health-diagnostic/report/hostsUsingSameName '{"limit": 10000}')
echo "$dup_hostnames" | jq '.data' > /tmp/dup_hostnames.json

# Get all deleted hosts (including permanently deleted)
echo "=== Fetching deleted hosts list ===" >&2
api_call GET /api/hosts/deleted?count=1000 | jq '.data' > /tmp/deleted_hosts_list.json

# Get agent run failures
echo "=== Fetching agent run failures ===" >&2
failures=$(api_call POST /api/query '{"query": "SELECT hostkey, lastagentlocalexecutiontimestamp, lastagentexecutionstatus FROM agentstatus WHERE lastagentexecutionstatus = '\''FAIL'\''"}')
echo "$failures" | jq '.data[0].rows' > /tmp/failures.json

# Get variables to check for inventory
echo "=== Fetching inventory variables ===" >&2
inventory=$(api_call POST /api/inventory '{"select": ["Host name", "Host key", "IPv4 address"], "limit": 10000}')
echo "$inventory" | jq '.rows' > /tmp/inventory.json

echo "=== Done collecting data ===" >&2
