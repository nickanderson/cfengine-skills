The script ran cleanly against the hub at `https://192.168.56.2` and printed **1123 hosts**, matching a `SELECT count(*) FROM hosts` check. Each line has exactly 3 comma-separated fields, all 1123 hostkeys are unique, and there are no blank fields or nulls in `hostkey`/`hostname`/`ipaddress` in the underlying view.

It queries the reporting database (`hosts` view, which drops deleted hosts and applies RBAC) via `/api/query`, paginating with `skip`/`limit` (page size 5000) so it can't silently truncate even if the hub ever caps a single response.

```bash
#!/usr/bin/env bash
# Print one CSV line per host known to CFEngine Mission Portal:
#   <hostkey>,<hostname>,<ip address>
# No header, nothing else on stdout.
#
# Needs MP_URL, MP_USER, MP_PASSWORD in the environment.
# MP_CACERT (path to the hub's certificate) is optional; without it,
# certificate verification is skipped (-k), since the hub uses a
# self-signed certificate.
set -euo pipefail

: "${MP_URL:?MP_URL is required}"
: "${MP_USER:?MP_USER is required}"
: "${MP_PASSWORD:?MP_PASSWORD is required}"

url=${MP_URL%/}

tls=(-k)
if [ -n "${MP_CACERT:-}" ]; then
  tls=(--cacert "$MP_CACERT")
fi

query() {  # query <sql> -> response body on stdout
  local sql=$1
  local body
  body=$(jq -n --arg q "$sql" --argjson skip "$skip" --argjson limit "$limit" \
    '{query: $q, skip: $skip, limit: $limit}')
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
    curl -sS --fail-with-body "${tls[@]}" -K - \
      -H 'Content-Type: application/json' --data-binary "$body" \
      "$url/api/query"
}

sql='SELECT hostkey, hostname, ipaddress FROM hosts'
skip=0
limit=5000

while :; do
  response=$(query "$sql")
  rowcount=$(printf '%s' "$response" | jq '.data[0].rowCount')

  printf '%s' "$response" |
    jq -r '.data[0].rows[] | map(tostring) | join(",")'

  [ "$rowcount" -lt "$limit" ] && break
  skip=$((skip + limit))
done
```

Notes:
- Requires `curl` and `jq`.
- Certificate verification is skipped (`-k`) since you said it's self-signed; set `MP_CACERT` to the hub's certificate file to verify properly instead.
- The password is piped to curl via `--netrc`-style stdin config, never passed as a `-u`/CLI argument, so it won't show up in `ps`.