I wrote `unhealthy-hosts.sh` in the working directory and ran it against the hub. It flagged 4 hosts, which matches the hub's own `totalFailed: 4`.

**Output:**
```
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
```

**How it works:**
- It asks `GET /api/health-diagnostic/status` for the count in each health category. It skips the two summary fields (`total` and `totalFailed`) and any category with a count of 0.
- For each remaining category, it sends `POST /api/health-diagnostic/report/<category>` and reads the host key from the first column of each row. It fetches results in pages of 1000 until it has every row.
- Category names are the Mission Portal internal names from the API: `deletedHostsReport`, `hostsUsingSameName`, `agentNotRunRecently`, `notRecentlyCollected`, `hostsNeverCollected`, `hostsUsingSameIdentity` and `lastAgentRunUnsuccessful`.
- The hub leaves out hosts that the logged-in user has dismissed on the Health page. So the output matches what `$MP_USER` sees there.
- Nothing but the result lines goes to stdout. If a request fails, it prints an error to stderr and exits with a non-zero code.
- It needs `curl` and `jq`, and skips certificate checks because the hub's certificate is self-signed.

```bash
#!/usr/bin/env bash
# List hosts flagged by Mission Portal's Health page as "<category>,<hostkey>".
# Requires: curl, jq. Env: MP_URL, MP_USER, MP_PASSWORD (self-signed cert OK).
set -euo pipefail

: "${MP_URL:?MP_URL not set}" "${MP_USER:?MP_USER not set}" "${MP_PASSWORD:?MP_PASSWORD not set}"
base="${MP_URL%/}/api/health-diagnostic"
page=1000

api() { # api <url> [json-body]  -> POST if a body is given
  if [ $# -gt 1 ]; then
    curl -skf -u "$MP_USER:$MP_PASSWORD" -X POST -H 'Content-Type: application/json' -d "$2" "$1"
  else
    curl -skf -u "$MP_USER:$MP_PASSWORD" "$1"
  fi
}

# Health summary: {"<category>": <count>, ..., "totalFailed": n, "total": n}
status=$(api "$base/status") || { echo "failed to query $base/status" >&2; exit 1; }

# Every key except the aggregate totals is a health category; skip empty ones.
categories=$(jq -r 'to_entries[]
  | select(.key != "total" and .key != "totalFailed")
  | select((.value|tonumber? // 0) > 0) | .key' <<<"$status")

for cat in $categories; do
  skip=0
  while :; do
    resp=$(api "$base/report/$cat" "{\"limit\":$page,\"skip\":$skip}") \
      || { echo "failed to query report $cat" >&2; exit 1; }
    # First column ("key") of every report is the host key.
    jq -r --arg c "$cat" '.data[0].rows[] | "\($c),\(.[0])"' <<<"$resp"
    got=$(jq '.data[0].rows | length' <<<"$resp")
    total=$(jq '.data[0].rowCount // 0' <<<"$resp")
    skip=$((skip + got))
    [ "$got" -gt 0 ] && [ "$skip" -lt "$total" ] || break
  done
done
```