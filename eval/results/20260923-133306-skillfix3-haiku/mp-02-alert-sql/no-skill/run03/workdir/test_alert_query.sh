#!/bin/bash
# Test the duplicate hostname detection query

echo "=== Testing alert condition query ==="
curl -k -s -u "$MP_USER:$MP_PASSWORD" \
  -X POST \
  -H "Content-Type: application/json" \
  "$MP_URL/api/query" \
  -d '{"query":"SELECT hostname, COUNT(DISTINCT hostkey) as host_count, array_agg(DISTINCT hostkey) as hostkeys FROM hosts GROUP BY hostname HAVING COUNT(DISTINCT hostkey) > 1 ORDER BY hostname;"}' 2>&1 | python3 -m json.tool
