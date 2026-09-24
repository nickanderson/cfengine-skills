#!/usr/bin/env bash
# Prints one CSV line per host known to CFEngine Enterprise Mission Portal:
#   <hostkey>,<hostname>,<ip address>
# No header, nothing else on stdout. Intended for feeding a CMDB.
#
# Requires: MP_URL, MP_USER, MP_PASSWORD
# Optional: MP_CACERT - path to the hub's certificate (self-signed hubs).
#           Without it, TLS verification is skipped (-k), since the hub's
#           certificate is self-signed and no certificate file was supplied.
#
# Depends on: curl, jq
set -euo pipefail

: "${MP_URL:?MP_URL is required, e.g. https://hub.example.com}"
: "${MP_USER:?MP_USER is required}"
: "${MP_PASSWORD:?MP_PASSWORD is required}"

for cmd in curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "all-hosts.sh: '$cmd' is required" >&2; exit 1; }
done

url=${MP_URL%/}
tls=(-k)
[ -n "${MP_CACERT:-}" ] && tls=(--cacert "$MP_CACERT")

# Query the reporting view directly (not the __hosts base table): it applies
# RBAC and excludes deleted hosts. /api/query has no default row limit
# (unlike GET /api/host, which silently caps at 50), so one call is enough.
run_query() {  # run_query <sql> -> response body on stdout
  local sql=$1 req
  req=$(jq -n --arg q "$sql" '{query: $q}')
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
    curl -sS --fail-with-body "${tls[@]}" -K - \
      -H 'Content-Type: application/json' \
      --data-binary "$req" \
      "$url/api/query"
}

hosts_json=$(run_query 'SELECT hostkey, hostname, ipaddress FROM hosts')
count_json=$(run_query 'SELECT count(*) AS n FROM hosts')

row_count=$(jq -r '.data[0].rowCount' <<<"$hosts_json")
hub_count=$(jq -r '.data[0].rows[0][0]' <<<"$count_json")

if [ "$row_count" != "$hub_count" ]; then
  echo "all-hosts.sh: got $row_count rows but the hub reports $hub_count hosts; aborting rather than risk an incomplete CMDB feed" >&2
  exit 1
fi

jq -r '.data[0].rows[] | @tsv' <<<"$hosts_json" | tr '\t' ','
