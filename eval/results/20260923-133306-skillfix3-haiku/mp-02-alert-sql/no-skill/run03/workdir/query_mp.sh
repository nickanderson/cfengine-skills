#!/bin/bash
# Try to access Mission Portal data APIs

echo "=== Checking for DataStore API ==="
curl -k -s -u "$MP_USER:$MP_PASSWORD" "$MP_URL/api/datastore" 2>&1 | head -30

echo -e "\n=== Checking for Hosts API ==="  
curl -k -s -u "$MP_USER:$MP_PASSWORD" "$MP_URL/api/hosts" 2>&1 | head -30

echo -e "\n=== Checking for available endpoints ==="
curl -k -s -u "$MP_USER:$MP_PASSWORD" "$MP_URL/index.html" 2>&1 | grep -i "api\|endpoint" | head -10
