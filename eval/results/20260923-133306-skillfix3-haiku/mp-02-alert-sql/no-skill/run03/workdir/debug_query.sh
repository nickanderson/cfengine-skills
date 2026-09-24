#!/bin/bash
# Debug the query API response

echo "=== Raw response ==="
curl -k -v -u "$MP_USER:$MP_PASSWORD" \
  -X POST \
  -H "Content-Type: application/json" \
  "$MP_URL/api/query" \
  -d '{"query":"SELECT hostname, COUNT(DISTINCT hostkey) as host_count FROM hosts GROUP BY hostname HAVING COUNT(DISTINCT hostkey) > 1"}' 2>&1 | head -100
