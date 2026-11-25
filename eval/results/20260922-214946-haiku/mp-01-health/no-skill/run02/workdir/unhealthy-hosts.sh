#!/bin/bash
set -euo pipefail

# Script to query CFEngine Enterprise Mission Portal for unhealthy hosts
# Output format: <category>,<hostkey>

MP_URL="${MP_URL:?Missing MP_URL environment variable}"
MP_USER="${MP_USER:?Missing MP_USER environment variable}"
MP_PASSWORD="${MP_PASSWORD:?Missing MP_PASSWORD environment variable}"

COOKIES_FILE=$(mktemp)
trap "rm -f $COOKIES_FILE" EXIT

# Log in to Mission Portal to get a valid session
csrf_token=$(curl -s -k -c "$COOKIES_FILE" "${MP_URL}/login/index" | grep -oP 'ci_csrf_token" value="\K[^"]+')
curl -s -k -b "$COOKIES_FILE" -c "$COOKIES_FILE" \
  -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${MP_USER}&password=${MP_PASSWORD}&ci_csrf_token=${csrf_token}&type_form=login&timezone=" \
  "${MP_URL}/login/index" > /dev/null

# Health diagnostic categories and their corresponding paths
declare -A categories=(
  ["unreachable-hosts"]="unreachable"
  ["missing-reporting-data"]="missing-data"
  ["outdated-reporting-data"]="outdated-data"
  ["policy-errors"]="policy-error"
  ["duplicate-ids"]="duplicate-key"
  ["duplicate-hostnames"]="duplicate-hostname"
  ["deleted-hosts-report"]="deleted-host"
)

# Fetch and parse each health diagnostic report
for report_path in "${!categories[@]}"; do
  category="${categories[$report_path]}"

  # Fetch the health diagnostic report page
  page=$(curl -s -k -b "$COOKIES_FILE" "${MP_URL}/reports/health-diagnostic/${report_path}")

  # Extract hostkeys from the HTML page
  # Look for hostkey patterns SHA=... in links or data
  echo "$page" | grep -oP 'SHA=[a-f0-9]{64}' | while read -r hostkey; do
    echo "${category},${hostkey}"
  done
done | sort -u
