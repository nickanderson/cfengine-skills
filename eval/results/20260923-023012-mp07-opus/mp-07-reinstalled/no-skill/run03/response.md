I've written and run the script. There is exactly one leftover record: host004's old key.

```
SHA=c80bed38648aaeb68773826a6fb9a874baab9373db69b95099ef065541de1869,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,host004.example.com,192.168.56.6
```

**How it decides.** Hostnames aren't a reliable way to tell machines apart here, so the script matches records by hardware ID instead. That ID (the machine's system UUID) stays the same when a machine is reinstalled, even though its host key changes:
- Both host004 records have the same hardware ID (`C2F8355A-…`). The old key last reported at 06:40:43 and the new key first reported at 06:41:25, so it's a clean handover.
- Two records both call themselves `hub.example.com` (192.168.56.2 and 192.168.56.5), but they have different hardware IDs and both are still reporting. They are two separate machines, not a reinstall, so they aren't listed. You may still want to check why the machine at .5 reports the hub's hostname.
- I didn't use network card (MAC) addresses: every VM shares `08:00:27:8d:c0:4d` on its NAT interface, so they would match everything.
- Records with no hardware ID aren't considered. That covers the placeholder `decomm01` and `lab-decomm01` entries (`SHA=evaldel…`).

**Assumptions:**
- Within a group of records with the same hardware ID, the one that reported most recently is the current one.
- An older record only counts as leftover if it stopped reporting before the current one first appeared. This stops two live cloned VMs that share a hardware ID from being flagged.
- The hostname and IP printed are the ones the machine reports under its current key.

The script only reads data and deletes nothing. It needs `curl` and `jq`.

`stale-records.sh`:
```bash
#!/usr/bin/env bash
# List Mission Portal host records left behind by reinstalled machines.
#
# A reinstall gives a machine a new CFEngine host key, but its hardware
# identity (SMBIOS system UUID, reported as dmi[system-uuid]) stays the same.
# Records sharing a system UUID are grouped; the record that reported most
# recently is the current one, and every other record in the group that
# stopped reporting before the current one first appeared is stale.
# (The overlap check avoids flagging cloned VMs that share a UUID but are
# both alive.) Hostname is deliberately NOT used as the key: distinct machines
# can report the same hostname.
#
# Output: <stale hostkey>,<current hostkey>,<hostname>,<ip>
# (hostname/ip are those the machine reports under its current record)
# Read-only: nothing is deleted.
#
# Requires: curl, jq. Env: MP_URL, MP_USER, MP_PASSWORD.
set -euo pipefail

: "${MP_URL:?MP_URL not set}" "${MP_USER:?MP_USER not set}" "${MP_PASSWORD:?MP_PASSWORD not set}"

SQL="SELECT h.hostkey, h.hostname, h.ipaddress,
       extract(epoch FROM h.firstreporttimestamp)::bigint AS firstseen,
       extract(epoch FROM h.lastreporttimestamp)::bigint AS lastseen,
       upper(trim(v.variablevalue)) AS uuid
FROM hosts h
JOIN variables v ON v.hostkey = h.hostkey
WHERE v.variablename = 'dmi[system-uuid]'"

payload=$(jq -n --arg q "$SQL" '{query: $q, limit: 1000000}')

resp=$(curl -sS -k --fail -u "$MP_USER:$MP_PASSWORD" \
  -H 'Content-Type: application/json' \
  -X POST "${MP_URL%/}/api/query" -d "$payload") || {
  echo "error: query to $MP_URL failed" >&2; exit 1; }

jq -r '
  .data[0].rows
  | map({key: .[0], hostname: .[1], ip: .[2],
         first: (.[3] | tonumber? // 0), last: (.[4] | tonumber? // 0),
         uuid: .[5]})
  # ignore missing/placeholder UUIDs that do not identify hardware
  | map(select(.uuid != null and .uuid != ""
                and (.uuid | test("^[0F-]+$") | not)))
  | group_by(.uuid)[]
  | select(length > 1)
  | sort_by(.last, .first)
  | last as $cur
  | .[:-1][]
  | select(.last <= $cur.first)
  | [.key, $cur.key, $cur.hostname, $cur.ip] | join(",")
' <<<"$resp"
```