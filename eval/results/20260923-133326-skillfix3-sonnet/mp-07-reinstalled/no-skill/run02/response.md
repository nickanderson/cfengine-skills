Clean output, exit 0, nothing on stderr. It correctly identifies `host004.example.com`'s leftover pre-reinstall record while ignoring the `hub.example.com` records that share a hostname but not an IP (so are two distinct machines, not a reinstall) and `host001.example.com`, which only has one record.

**Output of `./stale-records.sh` against the hub:**
```
SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5,host004.example.com,192.168.56.6
```

Final script (`stale-records.sh`):

```bash
#!/usr/bin/env bash
#
# stale-records.sh
#
# Finds leftover Mission Portal host records left behind when a machine was
# reinstalled and came back reporting under a new CFEngine host key.
#
# A machine's network identity (hostname, ip) is assumed stable across a
# reinstall, while its host key changes. So for every (hostname, ip) pair
# that has more than one distinct host key on record, the key with the most
# recent report is the machine's current identity, and every other key in
# that group is a leftover ("stale") record from before the reinstall.
#
# Records that merely share a hostname (or merely share an ip) but not both
# are treated as distinct machines and are not reported.
#
# Output (stdout), one line per leftover record, nothing else:
#   <stale hostkey>,<current hostkey>,<hostname>,<ip>
#
# Requires: curl, jq
# Uses env vars: MP_URL, MP_USER, MP_PASSWORD

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

curl -sk -u "${MP_USER}:${MP_PASSWORD}" \
    "${MP_URL%/}/api/host?limit=10000" \
| jq -r '
    .data
    # group records by their (hostname, ip) network identity
    | group_by([.hostname, .ip])
    | map(select(length > 1))
    | map(
        (max_by(.lastreport | tonumber)) as $current
        | .[]
        | select(.id != $current.id)
        | [.id, $current.id, .hostname, .ip]
        | @csv
      )
    | .[]
  ' \
| tr -d '"'
```

Note on approach: I queried the Mission Portal REST API (`/api/host`), which returned only 5 host records total. `host004.example.com` had two records sharing the same hostname *and* IP but different host keys — one that stopped reporting hours ago (the pre-reinstall leftover) and one actively reporting now (the post-reinstall current identity). `hub.example.com` also appeared twice, but with two different IPs, both still actively reporting — that's two distinct live machines that happen to share a hostname, not a reinstall, so the script correctly excludes it by requiring both hostname *and* IP to match before treating records as the same physical machine.