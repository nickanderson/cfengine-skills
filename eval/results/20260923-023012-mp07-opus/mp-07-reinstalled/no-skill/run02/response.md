I wrote `stale-records.sh` and ran it against the hub. It found one leftover record:

```
SHA=c80bed38648aaeb68773826a6fb9a874baab9373db69b95099ef065541de1869,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,host004.example.com,192.168.56.6
```

**How it tells machines apart:** the script matches records by each machine's hardware ID (the DMI system UUID the hub collects), not by hostname. Where one hardware ID appears under several host keys, the record that reported most recently is the current one and the rest are stale.

- **host004.example.com:** both of its records have the same hardware ID (`C2F8355A-…`). The old key stopped reporting at 06:40 and the new key has reported since 06:41, so the old record is left over from the reinstall.
- **hub.example.com:** two records share this hostname but are not leftovers. They have different hardware IDs and IPs (192.168.56.2 and .5), and both are still reporting. They look like two separate machines using the same hostname, so matching on hostname alone would have wrongly flagged one of them.
- **decomm01 / lab-decomm01:** these test records have no hardware ID, so they're ignored.

**Limitation:** a host that doesn't report a hardware ID, such as a non-Linux system or one without `dmidecode`, can't be matched and won't be listed.

The script only reads from the hub through `/api/query`; it doesn't delete anything.

```bash
#!/usr/bin/env bash
# List leftover Mission Portal host records from reinstalled machines.
# A physical/virtual machine is identified by its DMI system UUID
# (dmi[system-uuid]); hostnames alone are not unique (e.g. two distinct
# machines may both call themselves hub.example.com). For every UUID seen
# under more than one hostkey, the record with the latest last report is the
# current identity and every other record is stale.
# Output: <stale hostkey>,<current hostkey>,<hostname>,<ip>   (read-only)
set -euo pipefail
: "${MP_URL:?}" "${MP_USER:?}" "${MP_PASSWORD:?}"

read -r -d '' SQL <<'SQL' || true
WITH ident AS (
  SELECT h.hostkey, h.hostname, h.ipaddress,
         h.lastreporttimestamp, h.firstreporttimestamp,
         upper(trim(v.variablevalue)) AS uuid
  FROM hosts h
  JOIN variables v ON v.hostkey = h.hostkey
  WHERE v.variablename = 'dmi[system-uuid]'
    AND coalesce(trim(v.variablevalue), '') NOT IN ('', '0')
), ranked AS (
  SELECT *, row_number() OVER (PARTITION BY uuid
            ORDER BY lastreporttimestamp DESC NULLS LAST,
                     firstreporttimestamp DESC NULLS LAST, hostkey) AS rn
  FROM ident
)
SELECT s.hostkey, c.hostkey, c.hostname, c.ipaddress
FROM ranked s JOIN ranked c ON c.uuid = s.uuid AND c.rn = 1
WHERE s.rn > 1
ORDER BY c.hostname, s.hostkey
SQL

jq -n --arg q "$SQL" '{query: $q}' |
  curl -sSfk -u "$MP_USER:$MP_PASSWORD" -X POST \
       -H 'Content-Type: application/json' -d @- "$MP_URL/api/query" |
  jq -r '.data[0].rows[] | map(. // "") | join(",")'
```

It needs `curl` and `jq`. The `-k` flag skips certificate checks because the hub's certificate is self-signed.