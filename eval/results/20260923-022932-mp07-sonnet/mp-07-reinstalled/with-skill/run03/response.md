Clean exit, exactly one line on stdout, nothing on stderr.

## Findings

Against the hub, one leftover record was found:

```
SHA=c80bed38648aaeb68773826a6fb9a874baab9373db69b95099ef065541de1869,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,host004.example.com,192.168.56.6
```

`host004.example.com` (192.168.56.6) reported briefly under the old key until 06:40:43, then the new key took over at 06:41:25 and has kept reporting through now. I deliberately excluded two other candidates surfaced by the hub's own "duplicate hostname" check:

- **`hub.example.com`** appears under two different keys/IPs (192.168.56.2 and .5), but **both are still actively reporting right now** — that's a genuine hostname collision between two live machines, not a reinstall leftover, so it's not "stale."
- A **deleted host** (192.168.56.4) still attempting to report — it's already been removed from Mission Portal's host list, so there's no live record left to clean up, and it doesn't share a hostname with any current host.

## How it works

The script pulls `hostkey, hostname, ipaddress, lastreporttimestamp` (plus each host's learned `agentexecutioninterval` from `agentstatus`) via one read-only `POST /api/query`. For every hostname shared by more than one live record, it treats the record closest to "now" (within its own normal reporting cadence) as the *current* identity, and flags any sibling record whose last report has fallen behind that current one by more than its cadence allows as *stale*. Groups where every record is still reporting recently (like the `hub.example.com` case) are left alone.

```bash
#!/usr/bin/env bash
# stale-records.sh
#
# Finds Mission Portal host records left behind by machines that were
# reinstalled (and so now report under a new CFEngine host key, while the
# hub still keeps the old key's record).
#
# For every (hostname) shared by more than one live host record, the record
# whose last report is close to "now" (within its own learned reporting
# cadence) is treated as the machine's *current* identity; any other record
# for that same hostname whose last report has fallen far behind that
# current record's is treated as a *stale* leftover from a reinstall.
#
# Output: one line per leftover record, and nothing else on stdout:
#   <stale hostkey>,<current hostkey>,<hostname>,<ip>
#
# Read-only: issues a single SELECT via POST /api/query. Nothing is deleted.
#
# Required environment:
#   MP_URL       Mission Portal base URL, e.g. https://192.168.56.2
#   MP_USER      Mission Portal username
#   MP_PASSWORD  Mission Portal password
# Optional:
#   MP_CACERT    Path to the hub's CA/server certificate, for verified TLS.
#                If unset, certificate verification is skipped (-k), since
#                Mission Portal hubs commonly use a self-signed certificate.

set -u -o pipefail

: "${MP_URL:?MP_URL is not set}"
: "${MP_USER:?MP_USER is not set}"
: "${MP_PASSWORD:?MP_PASSWORD is not set}"

base_url="${MP_URL%/}"

if [ -n "${MP_CACERT:-}" ]; then
    curl_tls_opts=(--cacert "${MP_CACERT}")
else
    curl_tls_opts=(-k)
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "stale-records.sh: jq is required but not found in PATH" >&2
    exit 3
fi

# One row per record still sharing a hostname with the current, live
# identity for that host, whose own last report has fallen behind that
# current identity's by more than its normal reporting cadence
# (GREATEST(600s, 1.3x its learned agent-execution interval) -- the same
# floor Mission Portal's own "outdated reporting data" health check uses).
read -r -d '' sql <<'SQL'
WITH h AS (
  SELECT hosts.hostkey AS hostkey,
         hosts.hostname AS hostname,
         hosts.ipaddress AS ipaddress,
         hosts.lastreporttimestamp::timestamptz AS lastreport,
         COALESCE(agentstatus.agentexecutioninterval::numeric, 300) AS interval
  FROM hosts
  LEFT JOIN agentstatus ON agentstatus.hostkey = hosts.hostkey
),
grp AS (
  SELECT hostname, MAX(lastreport) AS max_last
  FROM h
  GROUP BY hostname
  HAVING COUNT(*) > 1
)
SELECT h.hostkey AS stale_hostkey,
       cur.hostkey AS current_hostkey,
       h.hostname AS hostname,
       cur.ipaddress AS ip
FROM h
JOIN grp ON grp.hostname = h.hostname
JOIN h cur ON cur.hostname = h.hostname AND cur.lastreport = grp.max_last
WHERE h.hostkey <> cur.hostkey
  AND extract(epoch FROM (grp.max_last - h.lastreport)) > GREATEST(600, h.interval * 1.3)
  AND extract(epoch FROM (now() - grp.max_last)) <= GREATEST(600, cur.interval * 1.3)
SQL

body=$(jq -n --arg q "$sql" '{query: $q}')

# Strip scheme and any path/port suffix to get the bare host curl's netrc
# machine matching needs.
host_no_scheme="${base_url#*://}"
host_only="${host_no_scheme%%/*}"
host_only="${host_only%%:*}"

response=$(curl -sS --fail-with-body "${curl_tls_opts[@]}" \
        --netrc-file <(printf 'machine %s\nlogin %s\npassword %s\n' \
            "$host_only" "$MP_USER" "$MP_PASSWORD") \
        -H 'Content-Type: application/json' \
        -X POST "$base_url/api/query" \
        --data-binary "$body")
status=$?

if [ "$status" -ne 0 ]; then
    echo "stale-records.sh: request to $base_url/api/query failed" >&2
    echo "$response" >&2
    exit "$status"
fi

echo "$response" | jq -r '.data[0].rows[]? | join(",")'
```

Note: certificate verification is skipped (`-k`) unless you set `MP_CACERT` to the hub's certificate file, since the hub uses a self-signed cert.