I wrote `stale-records.sh` and ran it against the hub. It found one leftover record: host004's old key.

**Output:**
```
SHA=c80bed38648aaeb68773826a6fb9a874baab9373db69b95099ef065541de1869,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,host004.example.com,192.168.56.6
```

**How it tells a reinstall from other duplicates:** matching on hostname alone gives the wrong answer here. The hub's "Duplicate hostnames" check flags two hostnames, but only one of them is a reinstall:

- **host004.example.com (a reinstall).** Both keys report the same hardware UUID (`dmi[system-uuid]` = `C2F8355A-…`). The old key last reported at 06:40:43, and the new key first reported at 06:41:25. The old record is the one listed as an "Unreachable host".
- **hub.example.com (not a reinstall).** The two records have different UUIDs and different IPs (.2 and .5), and both are still reporting. These are two separate machines using one name, so the script leaves them out. You should still look into the naming.

The script groups the records that exist now by hardware UUID. In each group, the newest identity is the current record. An older record counts as stale only if it stopped reporting before the current one first reported. That rule keeps cloned VMs that share a UUID but are both still running out of the results. Records with no usable UUID, or a placeholder one, are skipped.

The script only reads. It runs one SQL query through `POST /api/query` and changes nothing on the hub.

```bash
#!/usr/bin/env bash
# List Mission Portal host records left behind by reinstalled machines.
#
# A reinstalled machine gets a new host key but keeps its hardware (SMBIOS)
# UUID, inventoried as dmi[system-uuid]. Records sharing a UUID are the same
# machine; the newest identity is the current record, and an older record is
# stale if it stopped reporting before the current one first reported (so
# cloned VMs that share a UUID but both still report are not flagged).
#
# Output: <stale hostkey>,<current hostkey>,<hostname>,<ip>   (read-only)
#
# Env: MP_URL, MP_USER, MP_PASSWORD; optional MP_CACERT (PEM of the hub's
# certificate). Without MP_CACERT, TLS verification is skipped (-k).
set -euo pipefail

: "${MP_URL:?set MP_URL}" "${MP_USER:?set MP_USER}" "${MP_PASSWORD:?set MP_PASSWORD}"
command -v jq >/dev/null || { echo "stale-records.sh: jq is required" >&2; exit 1; }

if [[ -n "${MP_CACERT:-}" ]]; then tls=(--cacert "$MP_CACERT"); else tls=(-k); fi

read -r -d '' SQL <<'SQL' || true
WITH ident AS (
  SELECT h.hostkey, h.hostname, h.ipaddress,
         h.firstreporttimestamp AS firstseen,
         h.lastreporttimestamp  AS lastseen,
         upper(trim(v.variablevalue)) AS uuid
  FROM hosts h
  JOIN variables v ON v.hostkey = h.hostkey
  WHERE v.variablename = 'dmi[system-uuid]'
    AND trim(v.variablevalue) NOT IN ('', '0', 'Not Settable', 'Not Specified')
    AND upper(trim(v.variablevalue)) NOT IN ('00000000-0000-0000-0000-000000000000',
                                             'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF')
),
ranked AS (
  SELECT *, row_number() OVER (PARTITION BY uuid
                               ORDER BY firstseen DESC, lastseen DESC, hostkey) AS rn
  FROM ident
)
SELECT s.hostkey AS stale, c.hostkey AS current, c.hostname, c.ipaddress
FROM ranked c
JOIN ranked s ON s.uuid = c.uuid AND s.rn > 1
WHERE c.rn = 1
  AND s.lastseen <= c.firstseen
ORDER BY c.hostname, s.lastseen
SQL

body=$(jq -n --arg q "$SQL" '{query: $q}')
resp=$(curl -sS --fail-with-body "${tls[@]}" \
         --netrc-file <(printf 'machine %s login %s password %s\n' \
                          "$(sed -E 's#^[a-z]+://##; s#[:/].*##' <<<"$MP_URL")" \
                          "$MP_USER" "$MP_PASSWORD") \
         -H 'Content-Type: application/json' \
         --data-binary "$body" "${MP_URL%/}/api/query") || {
  echo "stale-records.sh: query failed: $resp" >&2; exit 2; }

jq -r '.data[0].rows[] | map(. // "") | join(",")' <<<"$resp"
```

**Notes:**
- **Certificate:** the script skips TLS verification (`-k`) because the certificate is self-signed. To verify it instead, set `MP_CACERT` to the path of the hub's certificate file (PEM format).
- **Credentials:** they reach curl through a temporary netrc, so the password never appears on a command line. A password containing spaces would break that netrc line.
- **Needs:** `bash`, `curl` 7.76 or newer (for `--fail-with-body`) and `jq`.
- **Which records it sees:** it only sees hosts your account is allowed to see, and only records that still exist. Hosts that are already deleted are excluded.
- **Cleanup:** it doesn't delete anything. When you're ready, `DELETE /api/host/<stale hostkey>` removes a leftover record.