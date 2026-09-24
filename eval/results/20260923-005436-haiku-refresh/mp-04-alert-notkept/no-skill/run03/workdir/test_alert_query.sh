#!/bin/bash
# Test script for CFEngine Enterprise alert query
# Run this on the hub: bash test_alert_query.sh

set -e

echo "=== CFEngine Enterprise Alert Query Test ==="
echo ""

# Check if we're running as root or can access cfpostgres
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must run as root"
    exit 1
fi

# Test database connectivity
echo "1. Testing database connectivity..."
su - cfpostgres -c "psql cfdb -c 'SELECT COUNT(*) as hosts_count FROM hosts;'" 2>/dev/null || {
    echo "ERROR: Cannot connect to cfdb database"
    exit 1
}

echo ""
echo "2. Checking for promise execution data..."
su - cfpostgres -c "psql cfdb -c 'SELECT COUNT(*) as total_executions FROM promise_executions WHERE outcome='\''not_kept'\'' LIMIT 1;'" 2>/dev/null

echo ""
echo "3. Running alert query..."
echo ""

# Run the actual alert query
su - cfpostgres -c "psql cfdb" << 'SQL'
-- Alert Query: Hosts with unfulfilled promises
SELECT DISTINCT h.hostkey, h.hostname
FROM hosts h
WHERE h.hostkey IN (
  SELECT DISTINCT pe.hostkey
  FROM promise_executions pe
  WHERE pe.outcome = 'not_kept'
    AND pe.timestamp >= (
      SELECT MAX(timestamp)
      FROM promise_executions
      WHERE hostkey = h.hostkey
    ) - INTERVAL '1 hour'
)
AND h.active = true
ORDER BY h.hostname;
SQL

echo ""
echo "4. Test complete!"
echo ""
echo "If you see hosts listed above, the alert is working correctly."
echo "If no hosts are shown, all promises are currently being kept."
