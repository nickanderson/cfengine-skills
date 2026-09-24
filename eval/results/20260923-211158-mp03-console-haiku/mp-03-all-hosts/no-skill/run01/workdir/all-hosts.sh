#!/bin/bash

set -e

# Get credentials from environment
MP_URL="${MP_URL:?Mission Portal URL not set}"
MP_USER="${MP_USER:?Mission Portal user not set}"
MP_PASSWORD="${MP_PASSWORD:?Mission Portal password not set}"

# Query the Mission Portal API for all hosts using SQL
# Returns: hostkey, hostname, ipaddress
curl -s -k -u "$MP_USER:$MP_PASSWORD" \
  -X POST "$MP_URL/api/query" \
  -H "Content-Type: application/json" \
  -d '{"query": "select hostkey, hostname, ipaddress from hosts"}' | \
  jq -r '.data[0].rows[] | @csv' | \
  sed 's/"//g'
