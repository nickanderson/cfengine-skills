#!/bin/bash
curl -sk -u "$MP_USER:$MP_PASSWORD" -H 'Content-Type: application/json' -X POST "$MP_URL/api/query" -d "$(jq -n --arg q "$1" '{query:$q}')"
