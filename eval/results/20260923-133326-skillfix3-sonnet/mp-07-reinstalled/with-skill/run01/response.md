Clean single-line output on stdout, as required.

## What it does

The script uses Mission Portal's own health-diagnostic categories rather than guessing at timestamp thresholds:

1. `hostsUsingSameName` (Duplicate hostnames) — gives every record that shares a hostname with another record.
2. `notRecentlyCollected` + `hostsNeverCollected` — gives records that have stopped communicating with the hub.

A record is a **leftover** if it appears in both: sharing a hostname with another record, *and* no longer reporting. The other record(s) sharing that hostname which *are* still reporting are candidates for "current." When more than one current candidate exists, it prefers the one with the same IP as the stale record (same physical machine), falling back to the most recently reporting one.

This correctly distinguished the two duplicate-hostname groups on this hub:
- `host004.example.com` — old key stopped reporting at 12:23:37, new key has been reporting ever since → flagged as a leftover.
- `hub.example.com` — two keys, two IPs, **both** still actively reporting right now → not a reinstall artifact, correctly skipped.

## Run against the hub

```
SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5,host004.example.com,192.168.56.6
```

One leftover record found: the old identity for `host004.example.com` (192.168.56.6) is stale; the machine now reports under the second hostkey shown.

The script only reads (`GET`/read-only `POST`s) — it deletes nothing.

```bash
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
```