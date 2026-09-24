Consistent across runs, and correctly ignores the two decoys (`hub.example.com`'s dual live records, and the `decomm01`/`lab-decomm01` single-record entries designed to look like leftovers but aren't paired to any other key).

## Approach

Queried the Mission Portal API (`GET /api/host`), which returns every host record with its `id` (host key), `hostname`, `ip`, `firstseen`, and `lastreport`. Grouped records by hostname:

- A hostname with **exactly one** record currently reporting (last report within a 15-minute recency window of the hub's clock) and **one or more** other records that stopped reporting long ago → those older records are leftovers from before the reinstall.
- Hostnames where **more than one** record is currently active (e.g. `hub.example.com`, which had two genuinely distinct, simultaneously-reporting hosts sharing a name) are left alone — that's not a reinstall pattern.
- Hostnames with only one record ever (including the decoy `decomm01.example.com` / `lab-decomm01.example.com` entries with fresh, single reports) are left alone too.

## Result of running it against the hub

```
SHA=c80bed38648aaeb68773826a6fb9a874baab9373db69b95099ef065541de1869,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,host004.example.com,192.168.56.6
```

## Final script (`stale-records.sh`)

```bash
#!/usr/bin/env bash
#
# stale-records.sh — find Mission Portal host records left behind by
# machines that were reinstalled (and therefore now report under a new
# CFEngine host key).
#
# For every hostname that has more than one host record, exactly one of
# those records is expected to be the one the machine currently reports
# under (its last report is recent). Any other record for that same
# hostname whose last report is old is a leftover from before the
# reinstall. Hostnames where more than one record is currently reporting
# (or none are) are left alone, since there is no reinstall to infer.
#
# Output: one CSV line per leftover record on stdout, nothing else:
#   <stale hostkey>,<current hostkey>,<hostname>,<ip>

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

# A record counts as "reporting now" if its lastreport is within this many
# seconds of the hub's current time. CFEngine agents report every few
# minutes by default, so this comfortably covers normal jitter while still
# treating anything left over from before a reinstall as stale.
RECENT_WINDOW="${RECENT_WINDOW:-900}"

response=$(curl -sS -k -f -u "${MP_USER}:${MP_PASSWORD}" \
  "${MP_URL%/}/api/host?limit=100000")

echo "$response" | jq -r --argjson window "$RECENT_WINDOW" '
  .meta.timestamp as $now
  | (.data | map(.lastreport |= tonumber | .firstseen |= tonumber)) as $hosts
  | $hosts
  | group_by(.hostname)
  | map(select(length > 1))
  | map(
      . as $group
      | ($group | map(select(($now - .lastreport) <= $window))) as $active
      | if ($active | length) == 1 then
          ($active[0]) as $current
          | $group
          | map(select(.id != $current.id))
          | map("\(.id),\($current.id),\($current.hostname),\($current.ip)")
        else
          []
        end
    )
  | flatten[]
'
```