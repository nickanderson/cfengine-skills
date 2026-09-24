I wrote `stale-records.sh` and ran it against the hub. It found one leftover record: host004's old key.

**Output:**
```
SHA=c80bed38648aaeb68773826a6fb9a874baab9373db69b95099ef065541de1869,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,host004.example.com,192.168.56.6
```

**How it tells records apart:** a reinstall gives a machine a new host key, but its hardware ID (the DMI system UUID from the dmidecode inventory) stays the same. So the script groups records by that UUID. In each group, the record that reported most recently is the current one and every other record is a leftover. The hostname and IP printed are the ones the machine reports under now.

**What the hub has:**
- **host004:** two keys, both with UUID `C2F8355A-…`. The old key `c80bed…` stopped reporting at 06:40 and the new key `714a84…` has reported since 06:41. That's a clear reinstall, so it's listed.
- **hub.example.com:** also appears under two keys, but these are not left over from a reinstall. They have different UUIDs and different IPs (.2 and .5), and both are still reporting. They're two separate machines, and the one at 192.168.56.5 is probably a client misconfigured to call itself `hub`. You may want to check that host.
- **decomm01 and lab-decomm01:** single records with placeholder IPs and no hardware UUID, so they aren't matched to anything. Records without a usable UUID, or with a known placeholder UUID, are always skipped rather than guessed at.

The script only reads from the hub; it doesn't delete anything. It prints nothing but the result lines on stdout, and errors go to stderr. It needs `curl` and `jq`.

```bash
#!/usr/bin/env bash
# List leftover Mission Portal host records from reinstalled machines.
#
# A reinstalled machine gets a new CFEngine host key but keeps its hardware
# identity (DMI system UUID). Records sharing a system UUID are the same
# machine; the one that reported most recently is its current record, and the
# others are stale.
#
# Output: <stale hostkey>,<current hostkey>,<hostname>,<ip>
# Requires: curl, jq. Env: MP_URL, MP_USER, MP_PASSWORD. Read-only.
set -euo pipefail

: "${MP_URL:?MP_URL not set}" "${MP_USER:?MP_USER not set}" "${MP_PASSWORD:?MP_PASSWORD not set}"

sql="SELECT h.hostkey, h.hostname, h.ipaddress,
            extract(epoch FROM h.lastreporttimestamp)::bigint,
            extract(epoch FROM h.firstreporttimestamp)::bigint,
            upper(trim(v.variablevalue))
     FROM hosts h
     JOIN variables v ON v.hostkey = h.hostkey
     WHERE v.variablename = 'dmi[system-uuid]'"

payload=$(jq -n --arg q "$sql" '{query: $q}')

resp=$(curl -sSk --fail -u "$MP_USER:$MP_PASSWORD" \
  -H 'Content-Type: application/json' -X POST \
  -d "$payload" "$MP_URL/api/query") || { echo "query API request failed" >&2; exit 1; }

jq -r '
  [ .data[0].rows[]
    | {key: .[0], host: (.[1] // ""), ip: (.[2] // ""),
       last: ((.[3] // "0") | tonumber), first: ((.[4] // "0") | tonumber),
       uuid: (.[5] // "")}
    # skip missing / placeholder UUIDs that do not identify hardware
    | select(.uuid != "" and (.uuid | test("^[0F-]+$") | not)
             and .uuid != "03000200-0400-0500-0006-000700080009"
             and (.uuid | test("NOT (SETTABLE|SPECIFIED|PRESENT)") | not))
  ]
  | unique_by(.key)
  | group_by(.uuid)[]
  | select(length > 1)
  | sort_by(.last, .first) | reverse
  | .[0] as $cur
  | .[1:][]
  | [.key, $cur.key, $cur.host, $cur.ip] | join(",")
' <<<"$resp"
```