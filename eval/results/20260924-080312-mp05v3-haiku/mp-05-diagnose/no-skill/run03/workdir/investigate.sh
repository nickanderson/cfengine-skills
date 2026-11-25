#!/bin/bash

MP_URL="$MP_URL"
MP_USER="$MP_USER"
MP_PASSWORD="$MP_PASSWORD"

echo "[*] Making raw curl requests to Mission Portal..."

# Try different endpoint patterns with curl
echo -e "\n[*] GET /api/"
curl -s -k -u "$MP_USER:$MP_PASSWORD" "$MP_URL/api/" | python3 -m json.tool | head -50

echo -e "\n\n[*] GET /api with different headers..."
curl -s -k -u "$MP_USER:$MP_PASSWORD" -H "Accept: application/json" "$MP_URL/api/"  | head -20

echo -e "\n\n[*] HEAD /api/"
curl -s -k -u "$MP_USER:$MP_PASSWORD" -I "$MP_URL/api/"

echo -e "\n\n[*] POST /api/ with query"
curl -s -k -u "$MP_USER:$MP_PASSWORD" -X POST -H "Content-Type: application/json" \
  -d '{"query": "hosts"}' "$MP_URL/api/" | head -20

