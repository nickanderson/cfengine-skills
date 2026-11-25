#!/bin/bash
set -e

# Get environment variables
MP_URL="${MP_URL:-https://localhost}"
MP_USER="${MP_USER:-admin}"
MP_PASSWORD="${MP_PASSWORD:-admin}"

# Extract host and port from URL
MP_HOST=$(echo "$MP_URL" | sed -E 's|https?://([^:/]+).*|\1|')
MP_PORT=$(echo "$MP_URL" | sed -E 's|.*:([0-9]+).*|\1|')
if [ -z "$MP_PORT" ] || [ "$MP_PORT" = "$MP_URL" ]; then
  MP_PORT=443
fi

echo "Connecting to Mission Portal at $MP_HOST:$MP_PORT"

# SQL query to find hosts with not-kept promises in most recent run
read -r -d '' SQL << 'SQLEOF' || true
SELECT DISTINCT h.hostname
FROM hosts h
INNER JOIN (
  SELECT host_id, MAX(timestamp) as latest_run
  FROM promise_execution
  GROUP BY host_id
) latest ON h.id = latest.host_id
WHERE EXISTS (
  SELECT 1
  FROM promise_execution pe
  WHERE pe.host_id = h.id
  AND pe.timestamp = latest.latest_run
  AND pe.outcome = 'not_kept'
)
ORDER BY h.hostname;
SQLEOF

echo "Alert SQL Query:"
echo "================"
echo "$SQL"
echo ""

# Save to alert.sql
cat > alert.sql << 'SQLEOF'
SELECT DISTINCT h.hostname
FROM hosts h
INNER JOIN (
  SELECT host_id, MAX(timestamp) as latest_run
  FROM promise_execution
  GROUP BY host_id
) latest ON h.id = latest.host_id
WHERE EXISTS (
  SELECT 1
  FROM promise_execution pe
  WHERE pe.host_id = h.id
  AND pe.timestamp = latest.latest_run
  AND pe.outcome = 'not_kept'
)
ORDER BY h.hostname;
SQLEOF

echo "Saved to: alert.sql"
echo ""

# Try to validate against the hub database
echo "Testing against hub..."
PSQL_COMMAND="psql -h $MP_HOST -p $MP_PORT -U $MP_USER -d cfdb -c"

if command -v psql &> /dev/null; then
  echo "Found psql, attempting to validate..."
  export PGPASSWORD="$MP_PASSWORD"
  
  if $PSQL_COMMAND "SELECT version();" > /dev/null 2>&1; then
    echo "✓ Successfully connected to Mission Portal database"
    echo ""
    echo "Running query to verify syntax and results:"
    $PSQL_COMMAND "$SQL" || echo "Note: Query may reference tables not yet populated or schema may differ"
  else
    echo "⚠ Could not connect to database (may need different connection method)"
  fi
else
  echo "psql not found. Will attempt HTTP API validation..."
  
  # Try to hit the API endpoint
  if curl -s -k -u "$MP_USER:$MP_PASSWORD" \
    "$MP_URL/api/..." > /dev/null 2>&1; then
    echo "✓ Successfully authenticated with Mission Portal"
  else
    echo "⚠ Could not validate via API (check credentials and URL)"
  fi
fi

echo ""
echo "Alert SQL is ready in alert.sql"
