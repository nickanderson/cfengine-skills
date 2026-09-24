Clean exit, clean stdout, no stderr noise. The script works as intended against the live hub.

## `unhealthy-hosts.sh`

```bash
#!/usr/bin/env bash
# Prints "<category>,<hostkey>" for every host flagged unhealthy on the
# Mission Portal Health page.
#
# Needs MP_URL, MP_USER, MP_PASSWORD; MP_CACERT (the hub's certificate) optional.
set -euo pipefail

: "${MP_URL:?MP_URL is not set}"
: "${MP_USER:?MP_USER is not set}"
: "${MP_PASSWORD:?MP_PASSWORD is not set}"

tls=(-k)
[ -n "${MP_CACERT:-}" ] && tls=(--cacert "$MP_CACERT")

mp_host=$(printf '%s' "$MP_URL" | sed -E 's#^[a-zA-Z]+://##; s#/.*##; s#:.*##')
netrc=$(printf 'machine %s login %s password %s\n' "$mp_host" "$MP_USER" "$MP_PASSWORD")

mp() { # mp <METHOD> <path> [json-body] -> response body; fails on HTTP errors
  local method="$1" path="$2"
  local -a body=()
  [ $# -ge 3 ] && body=(-H 'Content-Type: application/json' --data-binary "$3")
  curl -sS --fail-with-body "${tls[@]}" --netrc-file <(printf '%s' "$netrc") \
    -X "$method" "${body[@]}" "${MP_URL%/}/api${path}"
}

status=$(mp GET /health-diagnostic/status)

categories=$(printf '%s' "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

while IFS= read -r category; do
  [ -n "$category" ] || continue
  report=$(mp POST "/health-diagnostic/report/$category" '{"limit": 10000}')
  printf '%s' "$report" | jq -r --arg category "$category" \
    '.data[0].rows[]? | [$category, .[0]] | @csv' |
    sed 's/"//g'
done <<< "$categories"
```

Notes:
- It skips certificate verification (`-k`) unless `MP_CACERT` is set, since the hub uses a self-signed certificate.
- The password is passed to `curl` via a process-substituted netrc file, never as a `-u` argument or on the command line.
- Categories come from the keys of `/api/health-diagnostic/status` (minus `total`/`totalFailed`), since `report_ids` is known to omit `hostsUsingSameName`.
- The hostkey is taken from the first column (`key`) of each report, since column layouts differ per category.

Output from the actual run against the hub:

```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
hostsUsingSameName,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4
notRecentlyCollected,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4
```

One host (`SHA=714a84...`) shows up under both `hostsUsingSameName` and `notRecentlyCollected` — this overlap is expected: the Health page's summary counts each host once under its primary category, but the underlying report lists aren't mutually exclusive.