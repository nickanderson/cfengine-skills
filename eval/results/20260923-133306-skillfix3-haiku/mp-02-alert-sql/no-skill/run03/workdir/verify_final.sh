#!/bin/bash
# Verify the final alert query works

echo "=== Verifying final alert.sql query ==="
QUERY=$(cat alert.sql | tr '\n' ' ')
curl -k -s -u "$MP_USER:$MP_PASSWORD" \
  -X POST \
  -H "Content-Type: application/json" \
  "$MP_URL/api/query" \
  -d "{\"query\":\"$QUERY\"}" 2>&1 | python3 -m json.tool
