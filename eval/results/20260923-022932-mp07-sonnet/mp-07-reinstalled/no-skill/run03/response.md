The output correctly identifies the one leftover record (`host004.example.com`'s pre-reinstall key) and correctly excludes the `hub.example.com` pair, which shares a hostname but has two distinct IPs that are *both* still actively reporting — a genuine name coincidence, not a reinstall, so it's left alone.

**How it works:** it pages through `/api/host` (Mission Portal's Enterprise API), groups records by hostname, and within each group compares `lastreport` timestamps. If exactly one record in the group has the most recent `lastreport`, every other record in that group is a leftover pointing at it. If two or more are tied for most-recent, they're treated as separate live hosts and skipped. Nothing is deleted — it's read-only.

**Output from the run against the hub:**
```
SHA=c80bed38648aaeb68773826a6fb9a874baab9373db69b95099ef065541de1869,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,host004.example.com,192.168.56.6
```

```bash
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
```