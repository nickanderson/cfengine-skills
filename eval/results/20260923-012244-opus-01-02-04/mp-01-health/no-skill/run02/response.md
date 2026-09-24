I wrote `unhealthy-hosts.sh` and ran it against the hub. It flagged 4 hosts, which matches the `totalFailed: 4` count the hub reports for the Health page.

## Output

```
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
```

What the three categories mean:
- **deletedHostsReport:** 192.168.56.4 was deleted from the hub on 2026-09-22 but was still trying to report on 2026-09-23.
- **hostsUsingSameName:** two hosts with different keys (at 192.168.56.2 and 192.168.56.5) both call themselves `hub.example.com`.
- **agentNotRunRecently:** `host001.example.com` last ran its agent at 22:37 on 2026-09-22, although its latest report was collected at 06:20 on 2026-09-23.

## How it works

1. `GET /api/health-diagnostic/status` returns the Health page's summary, with a count for each category.
2. For each category with a count above zero, it calls `POST /api/health-diagnostic/report/<category>` and reads the `key` column, which holds the hostkey in every report. It fetches results in pages of 1000 using `limit` and `skip`.

I used the status summary for the category list rather than `/report_ids`. That's because `/report_ids` leaves out `hostsUsingSameName`, even though the Health page counts it. The reports also leave out hosts that have been dismissed on the Health page, so the output only shows what the page currently flags.

The script needs `curl` and `jq`. It skips certificate checks because the hub's certificate is self-signed.

## Script (`./unhealthy-hosts.sh`)

```bash
#!/usr/bin/env bash
# List hosts flagged as unhealthy on Mission Portal's Health page.
# Output: <category>,<hostkey>   (category = health-diagnostic report id)
# Requires: MP_URL, MP_USER, MP_PASSWORD; curl, jq.
set -euo pipefail

: "${MP_URL:?MP_URL not set}" "${MP_USER:?MP_USER not set}" "${MP_PASSWORD:?MP_PASSWORD not set}"
API="${MP_URL%/}/api/health-diagnostic"
PAGE=1000

api() { # api <method> <path> [json-body]
  curl -sSfk -u "$MP_USER:$MP_PASSWORD" -X "$1" \
       -H 'Content-Type: application/json' ${3:+-d "$3"} "$API/$2"
}

# The status summary lists every category the Health page counts (including
# hostsUsingSameName, which is missing from /report_ids) with its count.
status=$(api GET status)
categories=$(jq -r 'to_entries[]
  | select(.key != "total" and .key != "totalFailed")
  | select((.value | tonumber? // 0) > 0) | .key' <<<"$status")

for cat in $categories; do
  skip=0
  while :; do
    resp=$(api POST "report/$cat" "{\"limit\":$PAGE,\"skip\":$skip}")
    # Hostkey is in the column named "key" (present in every report).
    rows=$(jq -r '.data[0] as $d
      | ($d.header | map(.columnName) | index("key")) as $i
      | $d.rows[] | .[$i]' <<<"$resp")
    n=$(jq -r '.data[0].rows | length' <<<"$resp")
    [ -n "$rows" ] && sed "s/^/$cat,/" <<<"$rows"
    [ "$n" -lt "$PAGE" ] && break
    skip=$((skip + PAGE))
  done
done
```