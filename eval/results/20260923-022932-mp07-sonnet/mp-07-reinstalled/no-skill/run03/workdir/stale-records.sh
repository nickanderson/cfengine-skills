#!/usr/bin/env bash
# Find Mission Portal host records left behind by reinstalled machines.
#
# A machine that gets reinstalled shows up under a brand new hostkey while
# its old hostkey's record just stops reporting. We detect that by grouping
# host records by hostname: if several hostkeys share a hostname and exactly
# one of them is still reporting as recently as the newest record in the
# group, the others are leftover ("stale") records from before the reinstall.
# If more than one record in the group is tied for most-recent, they're
# treated as genuinely distinct, still-live hosts (e.g. a coincidental
# hostname clash) rather than a reinstall, and the group is skipped.
set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

page=1
while :; do
  resp=$(curl -sk -f -u "${MP_USER}:${MP_PASSWORD}" "${MP_URL}/api/host?page=${page}")
  n=$(printf '%s' "$resp" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))')
  if [ "$n" -eq 0 ]; then
    break
  fi
  printf '%s' "$resp" | python3 -c '
import json, sys
for h in json.load(sys.stdin)["data"]:
    print(json.dumps(h))
' >> "$tmpfile"
  page=$((page + 1))
done

python3 - "$tmpfile" <<'EOF'
import json
import sys
from collections import defaultdict

with open(sys.argv[1]) as f:
    hosts = [json.loads(line) for line in f if line.strip()]

by_hostname = defaultdict(list)
for h in hosts:
    by_hostname[h["hostname"]].append(h)

for hostname, records in by_hostname.items():
    if len(records) < 2:
        continue

    newest = max(int(r["lastreport"]) for r in records)
    current = [r for r in records if int(r["lastreport"]) == newest]
    if len(current) != 1:
        # Tie for most recent report: distinct still-live hosts, not a reinstall.
        continue
    current = current[0]

    for r in records:
        if int(r["lastreport"]) < newest:
            print(f'{r["id"]},{current["id"]},{hostname},{current["ip"]}')
EOF
