#!/usr/bin/env bash
# Find Mission Portal host records left over from a machine reinstall: an old
# hostkey that stopped reporting, while a new hostkey with the same hostname
# is currently reporting in its place.
#
# Needs MP_URL, MP_USER, MP_PASSWORD. MP_CACERT (the hub's certificate) is
# optional; without it, certificate verification is skipped (-k), since the
# hub is documented to use a self-signed certificate.
#
# Prints, for every leftover record found:
#   <stale hostkey>,<current hostkey>,<hostname>,<ip>
# Nothing else goes to stdout. Read-only: makes no changes on the hub.

set -euo pipefail

: "${MP_URL:?MP_URL is required}"
: "${MP_USER:?MP_USER is required}"
: "${MP_PASSWORD:?MP_PASSWORD is required}"

tls=(-k)
[ -n "${MP_CACERT:-}" ] && tls=(--cacert "$MP_CACERT")

mp() {  # mp <METHOD> <path> [json-body] -> response body on stdout
  local method="$1" path="$2"
  local -a body=()
  if [ $# -ge 3 ]; then
    body=(-H 'Content-Type: application/json' --data-binary "$3")
  fi
  printf 'machine %s\nlogin %s\npassword %s\n' \
    "$(printf '%s' "$MP_URL" | sed -E 's#^[a-zA-Z]+://##; s#/.*$##')" \
    "$MP_USER" "$MP_PASSWORD" |
    curl -sS --fail-with-body "${tls[@]}" --netrc-file /dev/stdin \
      -X "$method" "${body[@]}" "${MP_URL%/}$path"
}

# Records sharing a hostname with another record (Health page: Duplicate hostnames).
same_name_json=$(mp POST /api/health-diagnostic/report/hostsUsingSameName '{"limit": 10000}')

# Records that exist but are not currently communicating with the hub.
not_recent_json=$(mp POST /api/health-diagnostic/report/notRecentlyCollected '{"limit": 10000}')
never_json=$(mp POST /api/health-diagnostic/report/hostsNeverCollected '{"limit": 10000}')

stale_keys=$(
  {
    echo "$not_recent_json" | jq -r '.data[0].rows[]?[0] // empty'
    echo "$never_json" | jq -r '.data[0].rows[]?[0] // empty'
  } | sort -u
)

# hostkey<TAB>hostname<TAB>ip<TAB>lastreport, one row per record sharing its hostname.
same_name_rows=$(echo "$same_name_json" | jq -r '
  .data[0].rows[]? | [.[1], .[2], .[3], .[4]] | @tsv
')

is_stale() {
  grep -qxF "$1" <<<"$stale_keys"
}

# Group by hostname; within each group, records not flagged as stale are the
# "current" candidates a reinstalled machine could now be reporting under.
hostnames=$(printf '%s\n' "$same_name_rows" | cut -f2 | sort -u)

while IFS= read -r hostname; do
  [ -z "$hostname" ] && continue
  group=$(printf '%s\n' "$same_name_rows" | awk -F'\t' -v h="$hostname" '$2 == h')

  current_rows=$(printf '%s\n' "$group" | while IFS=$'\t' read -r hk hn ip lr; do
    is_stale "$hk" || printf '%s\t%s\t%s\t%s\n' "$hk" "$hn" "$ip" "$lr"
  done)
  [ -z "$current_rows" ] && continue  # no live record to attribute leftovers to

  while IFS=$'\t' read -r stale_hk hn stale_ip lr; do
    [ -z "$stale_hk" ] && continue
    is_stale "$stale_hk" || continue

    # Prefer the current record with the same IP (same machine); otherwise
    # fall back to whichever current record reported most recently.
    match=$(printf '%s\n' "$current_rows" | awk -F'\t' -v ip="$stale_ip" '$3 == ip' | head -1)
    if [ -z "$match" ]; then
      match=$(printf '%s\n' "$current_rows" | sort -t$'\t' -k4 | tail -1)
    fi

    current_hk=$(printf '%s' "$match" | cut -f1)
    current_ip=$(printf '%s' "$match" | cut -f3)

    printf '%s,%s,%s,%s\n' "$stale_hk" "$current_hk" "$hn" "$current_ip"
  done <<<"$group"
done <<<"$hostnames"
