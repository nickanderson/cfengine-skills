I wrote `unhealthy-hosts.sh` in the working directory and ran it against the hub at `$MP_URL`. It flagged four hosts, which matches the hub's own failed-host count (`totalFailed: 4`):

```
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
```

What the categories mean on the Health page:
- **`deletedHostsReport`**: the host was deleted from the hub but is still trying to report.
- **`hostsUsingSameName`** ("Duplicate hostnames"): two different host keys are reporting the same hostname.
- **`agentNotRunRecently`** ("Outdated reporting data"): the hub can reach the host, but its agent hasn't run recently.

The other four categories (missing reporting data, unreachable hosts, policy errors, duplicate IDs) had no hosts.

```bash
#!/usr/bin/env bash
# List hosts flagged by Mission Portal's Health page as "<category>,<hostkey>".
# Env: MP_URL, MP_USER, MP_PASSWORD; optional MP_CACERT (otherwise TLS
# verification is skipped, since the hub certificate is self-signed).
set -euo pipefail
: "${MP_URL:?MP_URL not set}" "${MP_USER:?MP_USER not set}" "${MP_PASSWORD:?MP_PASSWORD not set}"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

base=${MP_URL%/}
if [ -n "${MP_CACERT:-}" ]; then tls=(--cacert "$MP_CACERT"); else tls=(-k); fi

api() { # api METHOD PATH [BODY]
  local args=(-sS --fail-with-body "${tls[@]}" -X "$1")
  [ $# -ge 3 ] && args+=(-H 'Content-Type: application/json' --data-binary "$3")
  # Credentials go to curl on stdin, never on the command line.
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" | curl "${args[@]}" -K - "$base$2"
}

status=$(api GET /api/health-diagnostic/status)
# Categories come from /status keys (report_ids omits hostsUsingSameName).
for cat in $(jq -r 'to_entries[] | select(.key != "total" and .key != "totalFailed")
                    | select((.value|tonumber) > 0) | .key' <<<"$status"); do
  skip=0; limit=1000
  while :; do
    page=$(api POST "/api/health-diagnostic/report/$cat" "{\"skip\":$skip,\"limit\":$limit}")
    n=$(jq '.data[0].rows | length' <<<"$page")
    # First column ("key") is the hostkey in every report.
    jq -r --arg c "$cat" '.data[0].rows[] | "\($c),\(.[0])"' <<<"$page"
    [ "$n" -lt "$limit" ] && break
    skip=$((skip + limit))
  done
done
```

How it works:
- **Categories:** it reads them from the hub's health status summary rather than its list of report IDs, because that list leaves out "Duplicate hostnames."
- **Paging:** it pages through each report 1000 hosts at a time, so a large number of flagged hosts isn't cut off.
- **Credentials:** they reach curl on stdin, so the password doesn't show up in the process list.
- **Certificate:** it skips certificate verification (`-k`) because the certificate is self-signed. Set `MP_CACERT` to the hub's certificate file to turn verification on.
- **Requirements:** it needs `jq`.
- **Scope:** the Health page shows each host under only one category, the one closest to the root cause. Hosts you have dismissed on the Health page are hidden for your login, so the script doesn't list them either.