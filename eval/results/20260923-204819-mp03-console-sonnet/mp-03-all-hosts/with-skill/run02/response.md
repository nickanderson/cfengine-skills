All 1123 lines have exactly 3 comma-separated fields, all hostkeys are unique, no blank lines, no header — matches `meta.total`/`rowCount` from the `hosts` view (1123), which also matches `/api/health-diagnostic/status` `total` and `/api/host` `meta.total`, so nothing is being missed.

**Ran it against the hub: 1123 hosts printed.**

The script uses the reporting DB's `hosts` view via `/api/query` (not the paginated `/api/host` endpoint, which silently truncates at 50 unless you request more) and pages through with `skip`/`limit` so no host is dropped even on a hub large enough to exceed one response.

It needs `MP_URL`, `MP_USER`, `MP_PASSWORD` in the environment (matches your existing setup), plus `jq` and `curl`. Since the hub cert is self-signed and you didn't hand me a cert file, it skips TLS verification (`-k`) by default — set `MP_CACERT` to the hub's certificate to verify instead.

```bash
#!/usr/bin/env bash
# Prints one CSV line per host known to Mission Portal: hostkey,hostname,ipaddress
#
# Needs: MP_URL, MP_USER, MP_PASSWORD
# Optional: MP_CACERT (path to the hub's certificate; otherwise TLS verification is skipped)
set -euo pipefail

: "${MP_URL:?MP_URL must be set (e.g. https://hub.example.com)}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

tls=(-k)
[ -n "${MP_CACERT:-}" ] && tls=(--cacert "$MP_CACERT")

query() { # query <json-body> -> response body; fails on HTTP errors
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
    curl -sS --fail-with-body "${tls[@]}" -K - -X POST \
      -H 'Content-Type: application/json' --data-binary "$1" \
      "$MP_URL/api/query"
}

# The `hosts` view is RBAC-filtered and excludes deleted hosts (unlike the
# underlying __hosts table). Page with skip/limit so no host is dropped
# regardless of how many the hub holds.
page_size=5000
skip=0
sql='SELECT hostkey, hostname, ipaddress FROM hosts ORDER BY hostkey'

while :; do
  body=$(jq -n --arg q "$sql" --argjson skip "$skip" --argjson limit "$page_size" \
    '{query: $q, skip: $skip, limit: $limit}')
  resp=$(query "$body")

  rows=$(echo "$resp" | jq -r '.data[0].rows[] | @tsv')
  if [ -n "$rows" ]; then
    echo "$rows" | awk -F'\t' '{print $1","$2","$3}'
  fi

  got=$(echo "$resp" | jq '.data[0].rows | length')
  [ "$got" -lt "$page_size" ] && break
  skip=$((skip + page_size))
done
```