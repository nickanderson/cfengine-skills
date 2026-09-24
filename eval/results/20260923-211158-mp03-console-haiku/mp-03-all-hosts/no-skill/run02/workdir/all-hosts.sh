#!/bin/bash

set -euo pipefail

# Configuration from environment
MP_URL="${MP_URL}"
MP_USER="${MP_USER}"
MP_PASSWORD="${MP_PASSWORD}"

# Validate required variables
if [[ -z "$MP_URL" || -z "$MP_USER" || -z "$MP_PASSWORD" ]]; then
    echo "Error: MP_URL, MP_USER, and MP_PASSWORD must be set" >&2
    exit 1
fi

# Query the Mission Portal API for hosts
# Extract the hub and any other hosts from the API response
curl -s -k -u "${MP_USER}:${MP_PASSWORD}" "${MP_URL}/api/" | \
    jq -r '
    .data[] as $item |
    if $item.hub then
      [$item.hub.hostkey, $item.hub.hostname, $item.hub.ip] | @csv
    else
      empty
    end,
    if $item.hosts then
      .hosts[] | [.hostkey, .hostname, (.ip_address // .ip // "")] | @csv
    else
      empty
    end
    '

exit 0
