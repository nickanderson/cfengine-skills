I wrote `stale-records.sh` and ran it against the hub. It found one leftover record.

**Output:**
```
SHA=c80bed38648aaeb68773826a6fb9a874baab9373db69b95099ef065541de1869,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,host004.example.com,192.168.56.6
```

The old key for `host004.example.com` last reported at 06:40:43. The new key first reported 42 seconds later at 06:41:25 and is still reporting. The Health page also lists the old key as unreachable.

**How it decides.** The script treats a record as leftover only if another record with the same hostname first reported *after* it last reported. In other words, one key stopped and another took over. It matches on hostname and not IP, since a reinstall may come back with a different address. The IP printed is the one the machine reports now. If there's more than one possible current record, it prefers one with the same IP as the old record, then the one that reported most recently.

**What it doesn't list:**
- **`hub.example.com`** has two keys, but they're on different IPs (192.168.56.2 and .5) and both have been reporting at the same time since last night. That's two machines sharing a name, not a reinstall, so neither is listed. This is also why the Health page's "Duplicate hostnames" count is higher than the real number of leftovers.
- **SHA=d2224f…** at 192.168.56.4 has already been deleted, though it still tries to report. It no longer has a Mission Portal record, so there's nothing to clean up.

The script is read-only: it makes a single `POST /api/query` SQL query against the `hosts` view and deletes nothing. It needs `curl` and `jq`, and reads `MP_URL`, `MP_USER` and `MP_PASSWORD` from the environment. The password goes to curl through a process-substitution netrc, so it never appears on a command line. Because the certificate is self-signed, **it skips certificate verification (`-k`)** unless you set `MP_CACERT` to the hub's certificate file. One limitation: a password containing spaces would break the netrc line.

```bash
#!/usr/bin/env bash
# List Mission Portal host records left behind by reinstalled machines.
#
# A reinstalled machine reports under a new host key with the same hostname.
# A record is "stale" when another record with the same hostname first
# reported after the stale one last reported (their lifetimes do not
# overlap). Records with the same hostname that report side by side are
# distinct machines sharing a name, not reinstalls, and are not listed.
#
# Output: <stale hostkey>,<current hostkey>,<hostname>,<ip>  (ip = current)
# Read-only: uses only POST /api/query.
#
# Env: MP_URL, MP_USER, MP_PASSWORD; optional MP_CACERT (hub certificate,
# otherwise certificate verification is skipped with -k).
set -euo pipefail

: "${MP_URL:?MP_URL not set}" "${MP_USER:?MP_USER not set}" "${MP_PASSWORD:?MP_PASSWORD not set}"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

if [ -n "${MP_CACERT:-}" ]; then tls=(--cacert "$MP_CACERT"); else tls=(-k); fi

read -r -d '' SQL <<'SQL' || true
WITH h AS (
  SELECT hostkey, lower(hostname) AS hn, hostname, ipaddress,
         lastreporttimestamp AS lr, firstreporttimestamp AS fr
  FROM hosts
  WHERE hostname IS NOT NULL AND hostname <> ''
),
cur AS (
  SELECT * FROM h
  WHERE NOT EXISTS (SELECT 1 FROM h d
                    WHERE d.hn = h.hn AND d.hostkey <> h.hostkey AND d.fr >= h.lr)
),
pairs AS (
  SELECT DISTINCT ON (s.hostkey)
         s.hostkey AS stale, c.hostkey AS current, c.hostname, c.ipaddress
  FROM h s
  JOIN cur c ON c.hn = s.hn AND c.hostkey <> s.hostkey AND c.fr >= s.lr
  ORDER BY s.hostkey, (c.ipaddress = s.ipaddress) DESC, c.lr DESC
)
SELECT stale, current, hostname, ipaddress FROM pairs ORDER BY hostname, stale
SQL

body=$(jq -n --arg q "$SQL" '{query: $q, limit: 1000000}')

resp=$(curl -sS --fail-with-body "${tls[@]}" \
  --netrc-file <(printf 'machine %s login %s password %s\n' \
      "$(printf '%s' "$MP_URL" | sed -E 's#^[a-z]+://##; s#[:/].*$##')" "$MP_USER" "$MP_PASSWORD") \
  -H 'Content-Type: application/json' \
  --data-binary "$body" "${MP_URL%/}/api/query") || {
  echo "query failed: $resp" >&2; exit 2; }

jq -r '.data[0].rows[] | map(. // "") | join(",")' <<<"$resp"
```

When you're ready to clean up, you would remove the old record with `DELETE /api/host/SHA=c80bed38…`. I haven't run that, and won't without your go-ahead.