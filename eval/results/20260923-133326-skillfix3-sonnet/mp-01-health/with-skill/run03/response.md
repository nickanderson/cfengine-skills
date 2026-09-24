Output is clean — only the requested `<category>,<hostkey>` lines on stdout, matching the totals from `/api/health-diagnostic/status` (6 flagged rows across 4 categories with nonzero counts; the other 3 categories contributed no rows).

## unhealthy-hosts.sh

```bash
#!/usr/bin/env bash
# Lists hosts flagged unhealthy on the Mission Portal Health page.
#
# Needs: MP_URL, MP_USER, MP_PASSWORD
# Optional: MP_CACERT (path to the hub's certificate; without it, TLS
#           verification is skipped, since the hub uses a self-signed cert)
#
# Prints one line per flagged host to stdout:
#   <category>,<hostkey>
set -euo pipefail

: "${MP_URL:?Set MP_URL to the Mission Portal base URL}"
: "${MP_USER:?Set MP_USER to the Mission Portal username}"
: "${MP_PASSWORD:?Set MP_PASSWORD to the Mission Portal password}"

tls=(-k)
[ -n "${MP_CACERT:-}" ] && tls=(--cacert "$MP_CACERT")

mp() {  # mp <METHOD> <path> [json-body] -> response body; fails on HTTP errors
  local method=$1 path=$2 data=${3:-}
  local -a body=()
  [ -n "$data" ] && body=(-H 'Content-Type: application/json' --data-binary "$data")
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
    curl -sS --fail-with-body "${tls[@]}" -K - -X "$method" "${body[@]}" "$MP_URL$path"
}

status=$(mp GET /api/health-diagnostic/status)

categories=$(printf '%s' "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

while IFS= read -r category; do
  [ -z "$category" ] && continue
  report=$(mp POST "/api/health-diagnostic/report/$category" '{"limit":10000}')
  printf '%s' "$report" |
    jq -r --arg cat "$category" '.data[0].rows[]? | "\($cat),\(.[0])"'
done <<< "$categories"
```

**Output from the hub (192.168.56.2):**
```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
hostsUsingSameName,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4
notRecentlyCollected,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4
```

Notes:
- Requires `curl` and `jq`. Credentials come from `MP_URL`/`MP_USER`/`MP_PASSWORD` env vars, never hardcoded.
- TLS verification is skipped by default (`-k`) since the hub's certificate is self-signed; set `MP_CACERT` to a saved copy of the cert to verify properly instead.
- Categories are read dynamically from `/api/health-diagnostic/status` (rather than a hardcoded list or `/report_ids`, which is known to omit `hostsUsingSameName`), so it stays correct if the hub adds new health categories.
- A host can legitimately appear under more than one category (e.g. `SHA=714a...` here is both *Duplicate hostnames* and *Unreachable hosts*), since these are distinct problem categories, not a request for one line per unique host.