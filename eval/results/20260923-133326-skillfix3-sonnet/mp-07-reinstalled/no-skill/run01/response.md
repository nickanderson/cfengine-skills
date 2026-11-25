The script runs cleanly and prints exactly one leftover record, correctly excluding the hub's two legitimate concurrent records (different IPs, both actively reporting).

**How it works:** it pulls every record from `/api/host`, groups them by `(hostname, ip)`, and within any group with more than one record, treats the one with the newest `lastreport` as the machine's current identity and every other record in that group as a leftover from before reinstall. This correctly ignores `hub.example.com`'s two records, since they have different IPs and are both actively reporting (not a stale/current pair).

**Output against the hub:**
```
SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5,host004.example.com,192.168.56.6
```

Final script (`stale-records.sh`):

```bash
#!/usr/bin/env bash
# Find leftover Mission Portal host records left behind by reinstalled
# machines: a reinstalled machine keeps its hostname and IP but reports
# under a brand new host key, leaving its old record stuck in the
# inventory. We detect that by grouping all host records by
# (hostname, ip) and, within any group with more than one record,
# treating every record except the most-recently-reporting one as stale.
#
# Output (stdout only): <stale hostkey>,<current hostkey>,<hostname>,<ip>
# One line per leftover record. Nothing is deleted.

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

base_url="${MP_URL%/}"

# Pull every host record in one page (items set high enough to cover
# any realistic inventory; the hub reports a total in .meta so we size
# the request from that instead of hardcoding a magic number).
total=$(curl -sk -u "${MP_USER}:${MP_PASSWORD}" "${base_url}/api/host?items=1" \
  | jq -r '.meta.total')

curl -sk -u "${MP_USER}:${MP_PASSWORD}" "${base_url}/api/host?items=$((total > 0 ? total : 1))" \
| jq -r '
    .data
    | group_by([.hostname, .ip])
    | map(select(length > 1))
    | map(
        (max_by(.lastreport | tonumber)) as $current
        | .[]
        | select(.id != $current.id)
        | [.id, $current.id, .hostname, .ip]
        | join(",")
      )
    | .[]
  '
```