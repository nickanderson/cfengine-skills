#!/bin/bash
# Test Mission Portal API and HTTPS endpoint

echo "=== Testing HTTPS connection to Mission Portal ==="
curl -k -s -u "$MP_USER:$MP_PASSWORD" -I "$MP_URL/" 2>&1 | head -20

echo -e "\n=== Testing API endpoint for database info ==="
curl -k -s -u "$MP_USER:$MP_PASSWORD" "$MP_URL/api/tables" 2>&1 | head -50

echo -e "\n=== Checking for query endpoint ==="
curl -k -s -u "$MP_USER:$MP_PASSWORD" "$MP_URL/api/query" 2>&1 | head -50
