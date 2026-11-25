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
