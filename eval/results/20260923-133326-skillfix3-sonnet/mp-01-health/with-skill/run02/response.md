The output matches `/status` exactly: 1 + 1 + 3 + 1 = 6 rows total, one per category count, with no overlap collisions needed this run. The script is working correctly against the hub.

## `unhealthy-hosts.sh`

```bash
#!/usr/bin/env bash
# Prints "<category>,<hostkey>" for every host the Mission Portal Health page
# currently flags as unhealthy. Nothing else goes to stdout.
#
# Needs: MP_URL, MP_USER, MP_PASSWORD
# Optional: MP_CACERT (path to the hub's certificate; otherwise TLS verification is skipped)
set -euo pipefail

: "${MP_URL:?MP_URL is required}"
: "${MP_USER:?MP_USER is required}"
: "${MP_PASSWORD:?MP_PASSWORD is required}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

tls=(-k)
[ -n "${MP_CACERT:-}" ] && tls=(--cacert "$MP_CACERT")

mp() { # mp <METHOD> <path> [json-body] -> response body on stdout; fails on HTTP errors
  local -a body=()
  [ $# -ge 3 ] && body=(-H 'Content-Type: application/json' --data-binary "$3")
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
    curl -sS --fail-with-body "${tls[@]}" -K - -X "$1" "${body[@]}" "$MP_URL$2"
}

# Priority order matching the Health page: a host is reported only under the
# category closest to its root cause, so we assign each hostkey to the first
# matching category and skip it in any later one.
categories=(
  hostsNeverCollected
  notRecentlyCollected
  agentNotRunRecently
  lastAgentRunUnsuccessful
  hostsUsingSameIdentity
  hostsUsingSameName
  deletedHostsReport
)

status=$(mp GET /api/health-diagnostic/status)

declare -A seen=()

for category in "${categories[@]}"; do
  count=$(jq -r --arg c "$category" '.[$c] // 0' <<<"$status")
  [ "$count" -gt 0 ] || continue

  report=$(mp POST "/api/health-diagnostic/report/$category" '{"limit": 10000}')

  while IFS= read -r hostkey; do
    [ -n "$hostkey" ] || continue
    [ -n "${seen[$hostkey]:-}" ] && continue
    seen[$hostkey]=1
    echo "$category,$hostkey"
  done < <(jq -r '.data[0].rows[]? | .[0]' <<<"$report")
done
```

### Output from the live hub

```
notRecentlyCollected,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
hostsUsingSameName,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
```

This matches `/api/health-diagnostic/status`'s per-category counts (1+1+3+1=6, `totalFailed: 6`).

Notes/assumptions:
- Requires `MP_URL`, `MP_USER`, `MP_PASSWORD` in the environment, and `jq` on PATH.
- Skips TLS verification (`-k`) since the hub's certificate is self-signed and no `MP_CACERT` was given; pass `MP_CACERT=/path/to/cert.pem` to verify instead.
- Categories are queried in root-cause priority order (per Mission Portal's own diagnostic logic) and each hostkey is only emitted once, under its first matching category — this is needed because the per-category report lists can overlap even though `/status` counts each host once.