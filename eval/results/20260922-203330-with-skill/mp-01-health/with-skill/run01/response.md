Works cleanly — 4 flagged hosts total, matching `totalFailed` from `/api/health-diagnostic/status` (1 `agentNotRunRecently`, 1 `deletedHostsReport`, 2 `hostsUsingSameName`). Only the requested `<category>,<hostkey>` lines go to stdout; the TLS-verification warning goes to stderr.

## Script

```bash
#!/usr/bin/env bash
#
# Print one line per host flagged unhealthy on Mission Portal's Health page:
#   <category>,<hostkey>
#
# Requires: MP_URL, MP_USER, MP_PASSWORD in the environment.
# Optional: MP_CACERT (path to the hub's certificate). Without it, TLS
# verification is skipped (curl -k), since the hub uses a self-signed cert.
#
# Requires: curl, jq.

set -euo pipefail

: "${MP_URL:?Set MP_URL to the Mission Portal base URL, e.g. https://hub.example.com}"
: "${MP_USER:?Set MP_USER to a Mission Portal API username}"
: "${MP_PASSWORD:?Set MP_PASSWORD to the MP_USER account password}"

curl_opts=(-sS -u "${MP_USER}:${MP_PASSWORD}")
if [ -n "${MP_CACERT:-}" ]; then
    curl_opts+=(--cacert "${MP_CACERT}")
else
    curl_opts+=(-k)
    echo "unhealthy-hosts.sh: MP_CACERT not set, skipping TLS certificate verification" >&2
fi

base="${MP_URL%/}/api"

# The status endpoint's keys are the Health page categories (minus the two
# summary counters). report_ids is known to omit hostsUsingSameName, so the
# category list comes from here instead.
status=$(curl "${curl_opts[@]}" -X GET "${base}/health-diagnostic/status")

categories=$(jq -r 'keys[] | select(. != "total" and . != "totalFailed")' <<<"$status")

while IFS= read -r category; do
    [ -n "$category" ] || continue

    report=$(curl "${curl_opts[@]}" -X POST \
        -H "Content-Type: application/json" \
        -d '{"limit": 10000}' \
        "${base}/health-diagnostic/report/${category}")

    # Column 0 of every report is "key", the host's hostkey (SHA=...).
    echo "$report" | jq -r --arg cat "$category" \
        '.data[]?.rows[]? | [$cat, .[0]] | @csv' \
        | sed -e 's/^"//' -e 's/"$//' -e 's/","/,/'
done <<<"$categories"
```

## Output against the hub

```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
```

Notes:
- Skips TLS verification by default (self-signed cert); set `MP_CACERT` to the hub's certificate to verify properly instead.
- Categories come from `/api/health-diagnostic/status`'s keys rather than `report_ids`, since `report_ids` is known to omit `hostsUsingSameName` on this hub version.