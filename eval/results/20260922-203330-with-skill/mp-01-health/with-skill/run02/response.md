Confirmed: stdout has only the four `<category>,<hostkey>` lines, matching the hub's `totalFailed: 4` (1 outdated-reporting host, 1 deleted-but-still-reporting host, 2 duplicate-hostname hosts); the certificate warning goes to stderr.

The script queries `/api/health-diagnostic/status` for the live set of categories (rather than the incomplete `report_ids` endpoint, which omits `hostsUsingSameName`), then fetches each category's report and takes the first column (`key`) as the hostkey, per the mission-portal skill's documented Health-page behavior.

```bash
#!/usr/bin/env bash
# Prints one line per host flagged unhealthy on Mission Portal's Health page:
#   <category>,<hostkey>
#
# Required environment:
#   MP_URL       Mission Portal base URL, e.g. https://hub.example.com
#   MP_USER      API user
#   MP_PASSWORD  API user's password
# Optional:
#   MP_CACERT    Path to the hub's CA/server certificate. If unset, certificate
#                verification is skipped (-k), since the hub is known to use a
#                self-signed certificate.

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

curl_cert_args=()
if [ -n "${MP_CACERT:-}" ]; then
    curl_cert_args=(--cacert "$MP_CACERT")
else
    curl_cert_args=(-k)
    echo "unhealthy-hosts.sh: MP_CACERT not set; skipping certificate verification (-k)" >&2
fi

# Calls the API without ever putting the password on the command line (it
# would otherwise be visible to other users via `ps`). curl reads it from a
# tiny config fed on stdin instead.
api() {
    local method="$1" path="$2" data="${3:-}"
    local args=(-sS -f -X "$method" "${curl_cert_args[@]}" "$MP_URL$path")
    if [ -n "$data" ]; then
        args+=(-H "Content-Type: application/json" --data "$data")
    fi
    curl -K - "${args[@]}" <<CURLCFG
user = "$MP_USER:$MP_PASSWORD"
CURLCFG
}

status_json=$(api GET /api/health-diagnostic/status)

categories=$(printf '%s' "$status_json" | jq -r 'keys[] | select(. != "total" and . != "totalFailed")')

while IFS= read -r category; do
    [ -z "$category" ] && continue
    report_json=$(api POST "/api/health-diagnostic/report/$category" '{"limit": 100000}')
    printf '%s' "$report_json" | jq -r --arg cat "$category" '.data[0].rows[]? | $cat + "," + .[0]'
done <<< "$categories"
```

Output from running it against the hub:

```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
```

Notes:
- No `MP_CACERT` was provided, so it printed a certificate-verification warning to stderr and used `-k`; supply `MP_CACERT` to verify against the hub's actual cert instead.
- The password is never placed on the command line (visible via `ps`); it's fed to `curl` through a small stdin config instead.
- Requires `curl` and `jq` on the machine running it.