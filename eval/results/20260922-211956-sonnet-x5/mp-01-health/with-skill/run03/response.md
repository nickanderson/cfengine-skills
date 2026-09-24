Output matches the hub's status counts (1 + 1 + 2 = 4 flagged hosts, matching `totalFailed:4`). The script queries `/api/health-diagnostic/status` for the category list (since `report_ids` is known to omit `hostsUsingSameName` on 3.27.1), then paginates each category's report and takes the first column (`key`) as the hostkey, printing only `<category>,<hostkey>` lines.

Script output when run against the hub:

```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
```

Final script (`unhealthy-hosts.sh`):

```bash
#!/usr/bin/env bash
# Prints "<category>,<hostkey>" for every host the Mission Portal Health page
# currently flags as unhealthy.
#
# Required environment:
#   MP_URL       Mission Portal base URL, e.g. https://hub.example.com
#   MP_USER      API username
#   MP_PASSWORD  API password
# Optional:
#   MP_CACERT    Path to the hub's CA certificate. If unset, certificate
#                verification is skipped (-k) -- suitable for a hub with a
#                self-signed certificate.
set -euo pipefail

: "${MP_URL:?Set MP_URL to the Mission Portal base URL}"
: "${MP_USER:?Set MP_USER to the API username}"
: "${MP_PASSWORD:?Set MP_PASSWORD to the API password}"

mp_cert_opts=(-k)
if [ -n "${MP_CACERT:-}" ]; then
  mp_cert_opts=(--cacert "$MP_CACERT")
fi

# host[:port] portion of MP_URL, for the netrc "machine" line
mp_host=$(printf '%s\n' "$MP_URL" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##; s#/.*##')

mp_netrc() {
  printf 'machine %s login %s password %s\n' "$mp_host" "$MP_USER" "$MP_PASSWORD"
}

mp_api() {
  local method=$1 path=$2 body=${3:-}
  if [ -n "$body" ]; then
    curl -sS "${mp_cert_opts[@]}" --netrc-file <(mp_netrc) \
      -X "$method" -H 'Content-Type: application/json' -d "$body" \
      "$MP_URL$path"
  else
    curl -sS "${mp_cert_opts[@]}" --netrc-file <(mp_netrc) \
      -X "$method" \
      "$MP_URL$path"
  fi
}

# report_ids omits at least one category (hostsUsingSameName) on 3.27.1, so
# take the category list from status instead.
status=$(mp_api GET /api/health-diagnostic/status)
categories=$(printf '%s' "$status" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

while IFS= read -r category; do
  [ -n "$category" ] || continue

  skip=0
  limit=1000
  while :; do
    body=$(printf '{"skip":%d,"limit":%d}' "$skip" "$limit")
    resp=$(mp_api POST "/api/health-diagnostic/report/$category" "$body")

    # The first column ("key") is the hostkey in every category's report,
    # even though the remaining columns differ per category.
    printf '%s' "$resp" | jq -r --arg cat "$category" \
      '.data[0].rows[]? | [$cat, .[0]] | @csv' | tr -d '"'

    rowCount=$(printf '%s' "$resp" | jq -r '.data[0].rowCount // 0')
    [ "$rowCount" -lt "$limit" ] && break
    skip=$((skip + limit))
  done
done <<< "$categories"
```

Notes:
- Certificate verification is skipped (`-k`) by default since the hub uses a self-signed certificate; set `MP_CACERT` to a certificate file to verify instead.
- Credentials are read only from `MP_USER`/`MP_PASSWORD` and passed to curl via a netrc file built through process substitution, never as command-line arguments.