Verified against the live hub — matches the `/api/health-diagnostic/report/<category>` data that backs the Mission Portal Health page (I cross-checked each of the 7 category queries individually before scripting).

**Output from running `./unhealthy-hosts.sh` against the hub:**

```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
hostsUsingSameName,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4
notRecentlyCollected,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4
```

(Note: the hub's `/status` summary reports `hostsUsingSameName:3` while the actual report list returns 4 rows — a pre-existing discrepancy on the hub side between its summary counter and the detail query. I trusted the detail report, since that's the query that actually populates the Health page's host list.)

```bash
#!/usr/bin/env bash
# Print "<category>,<hostkey>" for every host currently flagged as unhealthy
# on the CFEngine Mission Portal Health page, using the hub's
# health-diagnostic REST API.
#
# Requires MP_URL, MP_USER, MP_PASSWORD in the environment. The hub's
# certificate is expected to be self-signed (curl is run with -k).

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

API="${MP_URL%/}/api/health-diagnostic"
AUTH=(-u "${MP_USER}:${MP_PASSWORD}")
CURL=(curl -sk --fail "${AUTH[@]}")

# Discover the set of health-diagnostic categories from the summary
# endpoint (it also includes categories missing from /report_ids, e.g.
# hostsUsingSameName), rather than hardcoding them.
status_json=$("${CURL[@]}" "${API}/status")

categories=$(jq -r 'del(.total, .totalFailed) | keys[]' <<<"$status_json")

while IFS= read -r category; do
    [ -z "$category" ] && continue

    report_json=$("${CURL[@]}" -X POST -H "Content-Type: application/json" \
        -d '{"limit": 100000}' "${API}/report/${category}")

    jq -r --arg cat "$category" '
        .data[0] as $d
        | ($d.header | map(.columnName) | index("key")) as $i
        | $d.rows[]?
        | "\($cat),\(.[$i])"
    ' <<<"$report_json"
done <<<"$categories"
```

The script is saved at `unhealthy-hosts.sh` in the working directory, and is executable.