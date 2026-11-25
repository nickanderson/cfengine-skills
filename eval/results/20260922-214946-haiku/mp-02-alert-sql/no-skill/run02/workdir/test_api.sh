#!/bin/bash

# Test alert SQL via Mission Portal API

MP_URL="${MP_URL}"
MP_USER="${MP_USER}"
MP_PASSWORD="${MP_PASSWORD}"

echo "Testing alert SQL via Mission Portal API..."
echo "URL: $MP_URL"
echo ""

# Try to test the SQL via the API endpoint
# Most Mission Portal instances have an API for running database queries

# First, try to get the API version/health check
echo "1. Checking Mission Portal connectivity..."
curl -s -k -u "$MP_USER:$MP_PASSWORD" \
    "$MP_URL/api/query" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{
      "query": "SELECT 1 as test"
    }' 2>&1 | head -20

echo ""
echo "2. Testing the alert SQL query..."
SQL_QUERY='SELECT hostname, COUNT(DISTINCT hostkey) as num_hosts FROM hosts WHERE hostname IS NOT NULL AND hostname != '\'''\'' GROUP BY hostname HAVING COUNT(DISTINCT hostkey) > 1 ORDER BY num_hosts DESC, hostname;'

curl -s -k -u "$MP_USER:$MP_PASSWORD" \
    "$MP_URL/api/query" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{
      \"query\": \"$SQL_QUERY\"
    }" 2>&1

echo ""
