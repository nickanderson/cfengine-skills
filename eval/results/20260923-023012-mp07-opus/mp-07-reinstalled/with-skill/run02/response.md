I wrote `stale-records.sh` and ran it against the hub. It found one leftover record:

```
SHA=c80bed38648aaeb68773826a6fb9a874baab9373db69b95099ef065541de1869,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,host004.example.com,192.168.56.6
```

**What I looked at on the hub:**
- **host004.example.com (192.168.56.6)**: this is the reinstalled machine. Its old key `c80bed…` last reported at 06:40:43. The new key `714a84…` first reported at 06:41:25 and is still reporting. The Health page lists the old key as unreachable.
- **hub.example.com**: two keys share this name, but they have different IPs (.2 and .5) and both are still reporting. These are two live machines with the same hostname, not a reinstall, so the script leaves them out. The name clash is still worth fixing.
- **192.168.56.4 (`d2224f…`)**: this record was already deleted but the machine is still trying to report. It isn't in Mission Portal's host list any more, so it isn't a leftover record either.

**How it decides:** a record counts as leftover when another record with the same hostname (ignoring case) first reported *after* this one last reported. That means the old key went quiet and a new key replaced it. The current key is the newest surviving record for that name, preferring one on the same IP. The hostname and IP printed are the ones the machine reports now. Everything runs as one read-only SQL query through `/api/query`, which avoids the 50-host page limit on `/api/host`.

**Setup:** it reads `MP_URL`, `MP_USER` and `MP_PASSWORD`, and needs `jq`. The password goes to curl through a temporary netrc, not on the command line. **It skips certificate checks (`-k`) by default** because the hub's certificate is self-signed. Set `MP_CACERT` to the hub's certificate file to turn checking on. It deletes nothing, and it exits with status 2 if the query fails.

```bash
#!/usr/bin/env bash
# stale-records.sh - list Mission Portal host records left behind by
# reinstalled machines (machine came back with a new host key).
#
# Prints one line per leftover record:
#   <stale hostkey>,<current hostkey>,<hostname>,<ip>
#
# A record is "leftover" when another record with the same hostname first
# reported *after* it last reported, i.e. the old identity went silent and a
# new one took its place. Records that are both still reporting (two live
# machines sharing a name) are not matched. The current record is the newest
# surviving identity for that hostname, preferring one on the same IP.
# Hostname and IP printed are those the machine reports now. Read-only.
#
# Environment: MP_URL, MP_USER, MP_PASSWORD (required)
#              MP_CACERT (optional; hub CA/cert file; without it TLS
#              verification is skipped, since the hub cert is self-signed)
set -euo pipefail

: "${MP_URL:?MP_URL not set}" "${MP_USER:?MP_USER not set}" "${MP_PASSWORD:?MP_PASSWORD not set}"
command -v jq >/dev/null || { echo "stale-records.sh: jq is required" >&2; exit 1; }

if [ -n "${MP_CACERT:-}" ]; then tls=(--cacert "$MP_CACERT"); else tls=(-k); fi

read -r -d '' SQL <<'SQL' || true
WITH h AS (
  SELECT hostkey, lower(hostname) AS name, hostname, ipaddress,
         firstreporttimestamp AS f, lastreporttimestamp AS l
  FROM hosts
  WHERE hostname IS NOT NULL AND hostname <> ''
),
superseded AS (
  SELECT s.* FROM h s
  WHERE EXISTS (SELECT 1 FROM h x
                WHERE x.name = s.name AND x.hostkey <> s.hostkey AND x.f > s.l)
),
current AS (
  SELECT * FROM h WHERE hostkey NOT IN (SELECT hostkey FROM superseded)
)
SELECT DISTINCT ON (s.hostkey)
       s.hostkey AS stale, c.hostkey AS current, c.hostname, c.ipaddress
FROM superseded s
JOIN current c ON c.name = s.name AND c.f > s.l
ORDER BY s.hostkey, (c.ipaddress IS NOT DISTINCT FROM s.ipaddress) DESC, c.l DESC, c.f DESC
SQL

body=$(jq -n --arg q "$SQL" '{query: $q}')
host=$(printf '%s' "$MP_URL" | sed -E 's#^[a-z]+://##; s#[/:].*$##')

resp=$(printf '%s' "$body" | curl -sS --fail-with-body "${tls[@]}" \
  --netrc-file <(printf 'machine %s login %s password %s\n' "$host" "$MP_USER" "$MP_PASSWORD") \
  -H 'Content-Type: application/json' --data-binary @- \
  "${MP_URL%/}/api/query") || { echo "stale-records.sh: query failed: $resp" >&2; exit 2; }

printf '%s' "$resp" | jq -r '.data[0].rows[] | map(. // "") | join(",")'
```

When you're ready to clean up, `DELETE /api/host/<stale hostkey>` removes each record. I haven't deleted anything.