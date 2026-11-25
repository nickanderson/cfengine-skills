The script runs cleanly and prints exactly one line — nothing else on stdout.

## Result against the hub

```
SHA=c80bed38648aaeb68773826a6fb9a874baab9373db69b95099ef065541de1869,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,host004.example.com,192.168.56.6
```

`host004.example.com` reported briefly under `SHA=c80bed3...` (06:40:26–06:40:43 UTC), then a new hostkey `SHA=714a840...` started reporting the same hostname/IP one minute later and has been reporting continuously since — a clean reinstall handoff.

Two other duplicate-hostname situations on the hub were deliberately **not** reported, since they aren't reinstall leftovers:
- `hub.example.com` has two hostkeys (192.168.56.5 and 192.168.56.2) that are *both* actively reporting right now, with heavily overlapping report windows — a real naming collision between two live hosts, not a stale identity.
- A genuinely deleted host (192.168.56.4) still attempting to report, and a `lab-decomm01.example.com` entry with an unrelated identity — neither shares a hostname with another live host.

The script distinguishes these by requiring the "stale" record's last report to fall entirely before the "current" record's first report (no time overlap) — a real reinstall handoff — rather than just matching on hostname.

```bash
#!/usr/bin/env bash
# Find leftover Mission Portal host records left behind by reinstalled
# machines: a reinstalled machine reports under a brand-new hostkey, but
# keeps reporting the same hostname, so the hub ends up with an old
# ("stale") record and a new ("current") record sharing that hostname.
#
# Prints one line per stale record:
#   <stale hostkey>,<current hostkey>,<hostname>,<ip>
#
# Requires: MP_URL, MP_USER, MP_PASSWORD in the environment. The hub
# certificate is self-signed, so verification is skipped unless MP_CACERT
# points at a certificate file to verify against.

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

cacert_opts=(-k)
if [ -n "${MP_CACERT:-}" ]; then
    cacert_opts=(--cacert "$MP_CACERT")
fi

# curl's netrc matching is by bare hostname, not the full URL.
mp_host=$(printf '%s' "$MP_URL" | sed -E 's#^[a-zA-Z]+://##; s#[:/].*$##')

# A hostname reported by more than one hostkey is a candidate. Among those
# hostkeys, the "current" one(s) are whichever last reported in the hub's
# most recent collection cycle (within 60s of the newest report seen
# anywhere). Any other hostkey for that hostname whose last report happened
# before the current record's first report is a leftover from a previous
# identity: it stopped reporting, and a new identity took over the name
# without any overlap. Hostkeys that overlap in time with the "current"
# one are a genuine, still-active naming collision, not a stale reinstall
# record, so they are left out.
read -r -d '' query <<'SQL' || true
WITH global_max AS (
    SELECT MAX(lastreporttimestamp) AS gm FROM hosts
),
dupes AS (
    SELECT hostkey, hostname, ipaddress, firstreporttimestamp, lastreporttimestamp
    FROM hosts
    WHERE hostname IN (SELECT hostname FROM hosts GROUP BY hostname HAVING COUNT(*) > 1)
),
current_hosts AS (
    SELECT d.hostkey AS current_hostkey, d.hostname AS hostname,
           d.ipaddress AS current_ip, d.firstreporttimestamp AS current_first
    FROM dupes d, global_max g
    WHERE d.lastreporttimestamp >= g.gm - interval '60 seconds'
)
SELECT d.hostkey AS stale_hostkey, c.current_hostkey, c.hostname, c.current_ip
FROM dupes d
JOIN current_hosts c ON d.hostname = c.hostname
WHERE d.hostkey <> c.current_hostkey
  AND d.lastreporttimestamp < c.current_first
SQL

body=$(jq -n --arg q "$query" '{query: $q}')

response=$(printf '%s' "$body" | curl -sS "${cacert_opts[@]}" \
    --netrc-file <(printf 'machine %s login %s password %s\n' "$mp_host" "$MP_USER" "$MP_PASSWORD") \
    -H 'Content-Type: application/json' \
    --data-binary @- \
    "$MP_URL/api/query")

echo "$response" | jq -r '.data[0].rows[]? | join(",")'
```

Note: the script uses `-k` (skip TLS verification) by default since the hub's certificate is self-signed; set `MP_CACERT=/path/to/cert.pem` to verify against it instead.