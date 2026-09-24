I investigated the hub's data before writing logic. `hostsUsingSameName` flagged two hostname groups: `host004.example.com` (2 records, one 50 minutes stale) and `hub.example.com` (2 records, both actively reporting seconds apart — a genuine duplicate-name situation, not a reinstall). The script uses the hub's own `notRecentlyCollected` diagnostic (its actual configured staleness threshold) to tell these apart, so it only reports records that truly stopped reporting in favor of a newer identity — correctly skipping the `hub.example.com` pair.

Output from running it against the hub:

```
SHA=c80bed38648aaeb68773826a6fb9a874baab9373db69b95099ef065541de1869,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,host004.example.com,192.168.56.6
```

Final script:

```bash
#!/usr/bin/env bash
# Find leftover Mission Portal host records left behind by machines that
# were reinstalled and now report under a new CFEngine identity (host key).
#
# For every hostname that Mission Portal has more than one record for, split
# the records into:
#   - "stale": records the hub's own health diagnostics consider not
#     recently collected (i.e. stopped reporting)
#   - "current": records that are still reporting
# When a hostname has both, each stale record is a leftover from before a
# reinstall, and the (single, most recently reporting) current record is
# the identity the machine reports under now. Hostnames where every record
# is still actively reporting are a genuine duplicate-hostname situation,
# not a reinstall, and are skipped.
#
# Output: one CSV line per leftover record, nothing else on stdout.
#   <stale hostkey>,<current hostkey>,<hostname>,<ip>
#
# Configuration (environment):
#   MP_URL       https://hub.example.com   (required)
#   MP_USER      Mission Portal login      (required)
#   MP_PASSWORD  Mission Portal password   (required)
#   MP_CACERT    path to the hub's certificate, for a self-signed hub
#                (if unset, certificate verification is skipped)

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

TLS_ARGS=(-k)
if [ -n "${MP_CACERT:-}" ]; then
  TLS_ARGS=(--cacert "$MP_CACERT")
fi

api() {  # api <method> <path> [json body] -> response body on stdout
  local method=$1 path=$2 data=${3-}
  local -a curlargs=(-sS -X "$method" "${TLS_ARGS[@]}"
                      --connect-timeout 10 --max-time 300
                      "${MP_URL%/}$path")
  if [ -n "$data" ]; then
    curlargs+=(-H "Content-Type: application/json" --data-binary "$data")
  fi
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" | curl -K - "${curlargs[@]}"
}

dup_json=$(api POST /api/health-diagnostic/report/hostsUsingSameName '{"limit":10000}')
stale_json=$(api POST /api/health-diagnostic/report/notRecentlyCollected '{"limit":10000}')

jq -rn \
  --argjson dup "$dup_json" \
  --argjson stale "$stale_json" \
  '
  ($stale.data[0].rows // []) | map(.[0]) as $stalekeys
  | ($dup.data[0].rows // []) as $rows
  | ($rows | group_by(.[2]))[]
  | . as $g
  | ($g | map(select(.[1] as $hk | ($stalekeys | index($hk)) != null))) as $staleset
  | ($g | map(select(.[1] as $hk | ($stalekeys | index($hk)) == null))) as $curset
  | select(($staleset | length) > 0 and ($curset | length) > 0)
  | ($curset | sort_by(.[4]) | last) as $cur
  | $staleset[]
  | "\(.[1]),\($cur[1]),\(.[2]),\($cur[3])"
  '
```

Notes:
- Standalone script (doesn't depend on the `mp-api.sh` wrapper) — takes credentials from `MP_URL`/`MP_USER`/`MP_PASSWORD` env vars, piping them to curl via stdin so the password never shows up in `ps`.
- Skips TLS verification by default (`-k`) since the hub uses a self-signed cert; set `MP_CACERT` to the hub's certificate to verify properly instead.
- If a hostname has more than one still-reporting record (like `hub.example.com` here — two distinct live hosts sharing a name), it's left out since there's no stale/leftover record to report.
- Nothing is deleted; the script only reads.