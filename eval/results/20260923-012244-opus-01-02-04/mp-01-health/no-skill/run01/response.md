I wrote `unhealthy-hosts.sh` and ran it against the hub. It printed four flagged hosts, which matches the Health page's own count of 4 (`totalFailed`).

**Output:**
```
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
```

**How it works:**
1. It calls `GET /api/health-diagnostic/status`, which returns a count for each Health category, and keeps every category with a count above zero. The `total` and `totalFailed` summary fields are skipped.
2. For each of those categories it calls `POST /api/health-diagnostic/report/<category>`, the same report the Health page uses, and prints each host key from the `key` column (the host key).
3. Hosts that the logged-in user has dismissed are already left out of these reports, so the output matches what that user sees on the Health page.

One category name to read with care: `deletedHostsReport` means a host that was deleted but is still trying to report to the hub. Each category name is printed exactly as the API returns it.

**unhealthy-hosts.sh:**
```bash
#!/usr/bin/env bash
# List hosts flagged as unhealthy on Mission Portal's Health page.
# Output: <category>,<hostkey>   (one line per flagged host)
# Requires: MP_URL, MP_USER, MP_PASSWORD; curl, python3.
set -euo pipefail
: "${MP_URL:?MP_URL not set}" "${MP_USER:?MP_USER not set}" "${MP_PASSWORD:?MP_PASSWORD not set}"
MP_URL="${MP_URL%/}"

api() { # api METHOD PATH [BODY]
  curl -sSfk -u "$MP_USER:$MP_PASSWORD" -H 'Content-Type: application/json' \
    -X "$1" ${3:+-d "$3"} "$MP_URL$2"
}

# Status endpoint returns per-category counts (plus totalFailed/total aggregates).
status=$(api GET /api/health-diagnostic/status)
categories=$(python3 -c '
import json, sys
for k, v in json.load(sys.stdin).items():
    if k in ("total", "totalFailed"): continue
    try:
        if int(v) > 0: print(k)
    except (TypeError, ValueError): pass
' <<<"$status")

for cat in $categories; do
  # Report rows exclude hosts the user dismissed, matching the Health page.
  # First column ("key") is the hostkey. Ask for enough rows to get them all.
  body=$(api POST "/api/health-diagnostic/report/$cat" '{"limit":1000}')
  total=$(python3 -c 'import json,sys;print(json.load(sys.stdin)["data"][0]["rowCount"])' <<<"$body")
  if [ "$total" -gt 1000 ]; then
    body=$(api POST "/api/health-diagnostic/report/$cat" "{\"limit\":$total}")
  fi
  python3 -c '
import json, sys
cat = sys.argv[1]
t = json.load(sys.stdin)["data"][0]
cols = [h["columnName"] for h in t["header"]]
i = cols.index("key") if "key" in cols else cols.index("hostkey")
seen = set()
for r in t["rows"]:
    hk = r[i]
    if hk and hk not in seen:
        seen.add(hk); print(f"{cat},{hk}")
' "$cat" <<<"$body"
done
```