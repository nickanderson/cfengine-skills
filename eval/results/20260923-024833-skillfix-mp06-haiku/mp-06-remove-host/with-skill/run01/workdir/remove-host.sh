#!/usr/bin/env bash
set -euo pipefail

hostname="${1:-}"

# Validate input
if [ -z "$hostname" ]; then
  echo "Usage: $0 <hostname>" >&2
  exit 1
fi

# Check for required environment variables
if [ -z "${MP_URL:-}" ] || [ -z "${MP_USER:-}" ] || [ -z "${MP_PASSWORD:-}" ]; then
  echo "Error: MP_URL, MP_USER, and MP_PASSWORD environment variables are required" >&2
  exit 1
fi

# Setup TLS options
tls=(-k)
[ -n "${MP_CACERT:-}" ] && tls=(--cacert "$MP_CACERT")

# Helper function to make API calls
mp() {
  local method=$1
  local path=$2
  local body=${3:-}

  local -a args=(
    -sS
    --fail-with-body
    "${tls[@]}"
    -X "$method"
  )

  if [ -n "$body" ]; then
    args+=(-H 'Content-Type: application/json' --data-binary "$body")
  fi

  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
    curl -K - "${args[@]}" "$MP_URL$path"
}

# Step 1: Find the host by hostname (paginate to handle large host lists)
echo "Finding host: $hostname" >&2
hostkey=""
page=1
found=false
while true; do
  result=$(mp GET "/api/host?page=$page&count=100")

  # Try to find the hostname in this page
  hostkey=$(echo "$result" | jq -r ".data[] | select(.hostname == \"$hostname\") | .id" 2>/dev/null | head -1)

  if [ -n "$hostkey" ]; then
    found=true
    break
  fi

  # Check if there are more pages
  total=$(echo "$result" | jq -r ".meta.total" 2>/dev/null || echo "0")
  if [ $(($page * 100)) -ge $total ]; then
    break
  fi

  page=$((page + 1))
done

if [ "$found" != true ] || [ -z "$hostkey" ]; then
  echo "Error: Host '$hostname' not found" >&2
  exit 1
fi

echo "Found hostkey: $hostkey" >&2

# Step 2: Delete the host (mark as deleted)
echo "Deleting host..." >&2
mp DELETE "/api/host/$hostkey" > /dev/null

# Step 3: Wait for the host to appear in deleted hosts (with timeout)
echo "Waiting for deletion to process..." >&2
timeout=30
elapsed=0
found_deleted=false
while [ $elapsed -lt $timeout ]; do
  deleted_result=$(mp GET "/api/hosts/deleted?skip=0&limit=1000")

  if echo "$deleted_result" | jq -e ".data[] | select(.hostkey == \"$hostkey\")" > /dev/null 2>&1; then
    found_deleted=true
    echo "Host marked as deleted" >&2
    break
  fi

  sleep 1
  elapsed=$((elapsed + 1))
done

if [ "$found_deleted" != true ]; then
  echo "Error: Host did not appear in deleted hosts list within timeout" >&2
  exit 1
fi

# Step 4: Permanently delete the host
echo "Permanently deleting host..." >&2
mp DELETE "/api/hosts/delete-permanently/$hostkey" > /dev/null

# Step 5: Verify the host is completely gone
echo "Verifying deletion..." >&2

# Check it's not in the regular host list
page=1
still_active=false
while true; do
  result=$(mp GET "/api/host?page=$page&count=100")

  if echo "$result" | jq -e ".data[] | select(.id == \"$hostkey\")" > /dev/null 2>&1; then
    still_active=true
    break
  fi

  total=$(echo "$result" | jq -r ".meta.total" 2>/dev/null || echo "0")
  if [ $(($page * 100)) -ge $total ]; then
    break
  fi

  page=$((page + 1))
done

if [ "$still_active" = true ]; then
  echo "Error: Host still exists in active hosts list" >&2
  exit 1
fi

# Check it's not in the deleted hosts list
deleted_result=$(mp GET "/api/hosts/deleted?skip=0&limit=1000")
if echo "$deleted_result" | jq -e ".data[] | select(.hostkey == \"$hostkey\")" > /dev/null 2>&1; then
  echo "Error: Host still exists in deleted hosts list" >&2
  exit 1
fi

echo "Host '$hostname' has been completely removed" >&2
exit 0
