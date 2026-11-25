Clean stdout, no stderr noise, exit code 0.

## Summary

I explored the CFEngine Enterprise REST API (`/api/health-diagnostic/status`, `/report_ids`, and `/report/:category`) to find the Health page's data source. The `report_ids` endpoint turned out to be an incomplete static list (missing `hostsUsingSameName`), so the script instead derives the category list from `/api/health-diagnostic/status`, which reports every category the hub currently tracks. For each category with a nonzero count, it POSTs to `/api/health-diagnostic/report/<category>` and extracts the `key` column (always the hostkey, per the API contract) from each row.

Run against the hub, it currently reports 4 unhealthy hosts:

```
agentNotRunRecently,SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
deletedHostsReport,SHA=d2224f7767ee9f3c7a6f7372b8096a4422e9331032976d2be95bd6fc126387dd
hostsUsingSameName,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
hostsUsingSameName,SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940
```

```bash
#!/usr/bin/env bash
#
# List hosts currently flagged as unhealthy on the CFEngine Mission Portal
# Health page, one "<category>,<hostkey>" line per flagged host.
#
# Requires: MP_URL, MP_USER, MP_PASSWORD in the environment. curl, jq.

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

curl_json() {
    # $1 = HTTP method, $2 = path (after /api), rest = extra curl args
    local method="$1" path="$2"
    shift 2
    curl -sk -u "${MP_USER}:${MP_PASSWORD}" -X "${method}" \
        "${MP_URL%/}/api${path}" "$@"
}

# The set of health-diagnostic categories is whatever the hub's status
# endpoint reports (excluding the aggregate "total"/"totalFailed" fields).
# This is more robust than the report_ids endpoint, which is known to omit
# at least one valid category (hostsUsingSameName).
status_json=$(curl_json GET /health-diagnostic/status)

categories=$(jq -r 'keys[] | select(. != "total" and . != "totalFailed")' <<<"${status_json}")

while IFS= read -r category; do
    [ -z "${category}" ] && continue

    count=$(jq -r --arg c "${category}" '.[$c]' <<<"${status_json}")
    # Status may report "n/a" for categories the user lacks permission to view.
    [ "${count}" = "0" ] && continue
    [ "${count}" = "n/a" ] && continue

    report_json=$(curl_json POST "/health-diagnostic/report/${category}" \
        -H 'Content-Type: application/json' -d '{}')

    jq -r --arg cat "${category}" \
        '.data[0].rows[] | [$cat, .[0]] | @csv' <<<"${report_json}" \
        | tr -d '"'
done <<<"${categories}"
```