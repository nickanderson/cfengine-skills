I wrote `unhealthy-hosts.sh` and ran it against the hub. It printed four flagged hosts, which matches the hub's own count of 4 failed hosts. It exited 0 and printed nothing else to stdout.

**Output from the hub:**
```
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
```

What the categories mean:
- **`deletedHostsReport`:** 192.168.56.4 was deleted from the hub but is still trying to report.
- **`hostsUsingSameName` (Duplicate hostnames):** two different host keys both report the name `hub.example.com`, from 192.168.56.2 and 192.168.56.5.
- **`agentNotRunRecently` (Outdated reporting data):** `host001.example.com` is still reachable, but its agent last ran at 22:37 on 2026-09-22.

**`unhealthy-hosts.sh`:**
```bash
#!/usr/bin/env bash
# List hosts flagged on Mission Portal's Health page, one "<category>,<hostkey>" per line.
# Needs: MP_URL, MP_USER, MP_PASSWORD. Optional: MP_CACERT (hub certificate;
# without it, TLS verification is skipped because the hub cert is self-signed).
set -euo pipefail

: "${MP_URL:?MP_URL is not set}" "${MP_USER:?MP_USER is not set}" "${MP_PASSWORD:?MP_PASSWORD is not set}"
base=${MP_URL%/}

if [ -n "${MP_CACERT:-}" ]; then tls=(--cacert "$MP_CACERT"); else tls=(-k); fi

# Credentials go to curl via a process-substitution netrc, never on the command line.
host=$(printf '%s' "$base" | sed -E 's#^[a-z]+://##; s#[:/].*##')
api() { # api METHOD PATH [BODY]
  local args=(-sS --fail-with-body "${tls[@]}" -X "$1")
  [ $# -ge 3 ] && args+=(-H 'Content-Type: application/json' --data "$3")
  curl "${args[@]}" \
    --netrc-file <(printf 'machine %s login %s password %s\n' "$host" "$MP_USER" "$MP_PASSWORD") \
    "$base$2"
}

# Categories come from /status keys (report_ids omits hostsUsingSameName).
status=$(api GET /api/health-diagnostic/status) || { echo "status request failed: $status" >&2; exit 1; }
categories=$(jq -r 'to_entries[] | select(.key != "total" and .key != "totalFailed")
                    | select((.value|tonumber) > 0) | .key' <<<"$status")

for cat in $categories; do
  skip=0; limit=1000
  while :; do
    resp=$(api POST "/api/health-diagnostic/report/$cat" "{\"skip\":$skip,\"limit\":$limit}") \
      || { echo "report $cat failed: $resp" >&2; exit 1; }
    # First column ("key") is the hostkey in every report.
    n=$(jq '.data[0].rows | length' <<<"$resp")
    jq -r --arg c "$cat" '.data[0].rows[] | "\($c),\(.[0])"' <<<"$resp"
    [ "$n" -lt "$limit" ] && break
    skip=$((skip + limit))
  done
done
```

How it works:
- **Categories:** it gets the list from the keys of `/api/health-diagnostic/status`, not from `report_ids`. On this hub (3.27.1), `report_ids` leaves out `hostsUsingSameName`, and that category has two hosts right now.
- **Host keys:** it takes each host key from the first column (`key`) of each report. Some reports have no `hostkey` column, so that is the only column every report has.
- **Paging:** it fetches each report 1,000 hosts at a time, so large reports aren't cut off.
- **What counts as unhealthy:** a host shows up under one category only, the one closest to the root cause. I included deleted hosts that are still trying to report because the hub counts them in its failed total. Hosts that you, logged in as `$MP_USER`, dismissed on the Health page are left out, just as they are on the page.
- **Password:** it goes to curl as a temporary netrc file, so it never appears on the command line or in the process list.
- **Certificate:** by default it runs curl with `-k`, which **skips certificate checks** because your certificate is self-signed. To turn checking back on, set `MP_CACERT=/path/to/hub-cert.pem`.
- **Requirements:** it needs `curl` and `jq`.