#!/bin/bash
# Use the Mission Portal query API to discover the schema

echo "=== Discovering database tables ==="
curl -k -s -u "$MP_USER:$MP_PASSWORD" \
  -X POST \
  -H "Content-Type: application/json" \
  "$MP_URL/api/query" \
  -d '{"query":"SELECT table_name FROM information_schema.tables WHERE table_schema='"'"'public'"'"' ORDER BY table_name LIMIT 30"}' 2>&1 | python3 -m json.tool

echo -e "\n=== Sample query from hosts table ==="
curl -k -s -u "$MP_USER:$MP_PASSWORD" \
  -X POST \
  -H "Content-Type: application/json" \
  "$MP_URL/api/query" \
  -d '{"query":"SELECT * FROM hosts LIMIT 3"}' 2>&1 | python3 -m json.tool | head -80
