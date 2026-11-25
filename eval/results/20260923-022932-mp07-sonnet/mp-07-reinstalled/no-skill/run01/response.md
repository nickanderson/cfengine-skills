Clean run, one stale record found, nothing extraneous on stdout, no errors.

## Approach

Mission Portal's `/api/host` report lists every host key record the hub knows about (current and stale alike), each with `hostname`, `ip`, a `lastreport` timestamp, and its host key (`id`). I grouped records by hostname, and for each hostname with more than one record, compared how recently each key last reported (relative to the API response's own `meta.timestamp`, to avoid clock skew):

- Exactly one record still checking in recently (≤10 min, `STALE_AFTER_SECONDS`, configurable) → that's the machine's current identity.
- Any other record(s) for that hostname that have gone quiet → leftovers from before the reinstall.
- If zero or more than one record is currently live for a hostname, it's left alone — that's either two genuinely distinct hosts sharing a name (seen in the eval data: `hub.example.com` under two different live IPs) or no live host to attribute leftovers to.

Against the hub, this correctly found one leftover pair (`host004.example.com`, same IP, old key stopped ~50 min ago while a new key took over ~42s later and is still reporting), and correctly ignored the `hub.example.com` hostname collision (both records live) and the standalone decoy/decommissioned records.

## Output from the run

```
SHA=c80bed38648aaeb68773826a6fb9a874baab9373db69b95099ef065541de1869,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,host004.example.com,192.168.56.6
```

## Script (`stale-records.sh`)

```bash
#!/usr/bin/env bash
#
# stale-records.sh
#
# Finds leftover Mission Portal host records left behind by machines that
# were reinstalled (and so now report under a new CFEngine host key).
#
# For every hostname that has more than one host record, we look at how
# recently each record's key last reported in. If exactly one record for
# that hostname is currently reporting (age <= STALE_AFTER_SECONDS) and one
# or more other records for the same hostname have gone quiet, the quiet
# ones are the leftovers from before the reinstall and the reporting one is
# the machine's current identity.
#
# If a hostname has zero or more than one currently-reporting record, we
# leave it alone: that's either two genuinely distinct live hosts sharing a
# hostname, or a hostname with no live host to attribute the leftovers to.
#
# Output (stdout, nothing else): one CSV line per leftover record:
#   <stale hostkey>,<current hostkey>,<hostname>,<ip>
#
# Required environment: MP_URL, MP_USER, MP_PASSWORD
# Optional environment: STALE_AFTER_SECONDS (default 600)

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"
STALE_AFTER_SECONDS="${STALE_AFTER_SECONDS:-600}"

CURL=(curl -sk -u "${MP_USER}:${MP_PASSWORD}")

# Mission Portal's /api/host report lists every host record the hub knows
# about (current and stale alike) along with when each one was last heard
# from, so it doesn't need paging for the sizes involved here; pull a large
# page just in case the hub has a lot of hosts.
response="$("${CURL[@]}" "${MP_URL%/}/api/host?items=1000000")"

if ! printf '%s' "$response" | jq -e '.data' >/dev/null 2>&1; then
    echo "stale-records.sh: unexpected response from ${MP_URL}/api/host" >&2
    printf '%s\n' "$response" >&2
    exit 1
fi

printf '%s' "$response" | python3 -c '
import json
import sys
from collections import defaultdict

payload = json.load(sys.stdin)
now = int(payload["meta"]["timestamp"])
threshold = int(sys.argv[1])

by_hostname = defaultdict(list)
for host in payload["data"]:
    by_hostname[host["hostname"]].append(host)

for hostname, records in by_hostname.items():
    if len(records) < 2:
        continue

    active = [r for r in records if now - int(r["lastreport"]) <= threshold]
    stale = [r for r in records if now - int(r["lastreport"]) > threshold]

    if len(active) != 1 or not stale:
        # Either multiple records are simultaneously live (distinct hosts
        # that happen to share a hostname) or none are live (no current
        # identity to attribute the leftovers to) -- skip.
        continue

    current_id = active[0]["id"]
    current_ip = active[0]["ip"]
    for old in stale:
        print(",".join([old["id"], current_id, hostname, current_ip]))
' "$STALE_AFTER_SECONDS"
```