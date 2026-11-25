#!/bin/bash

# Find stale host records in CFEngine Mission Portal
# Prints one line per stale record: <stale hostkey>,<current hostkey>,<hostname>,<ip>

MP_URL="${MP_URL:?MP_URL not set}"
MP_USER="${MP_USER:?MP_USER not set}"
MP_PASSWORD="${MP_PASSWORD:?MP_PASSWORD not set}"

# Create temporary Python script
PYTEMP=$(mktemp)
trap "rm -f $PYTEMP" EXIT

cat > "$PYTEMP" << 'PYSCRIPT'
import json
import sys

try:
    response = json.load(sys.stdin)
    rows_data = response.get('data', [])
    if not rows_data or len(rows_data) == 0:
        sys.exit(0)

    result = rows_data[0]
    headers = result.get('header', [])
    rows = result.get('rows', [])

    col_map = {}
    for i, col in enumerate(headers):
        col_map[col.get('columnName')] = i

    hosts = []
    for row in rows:
        if 'hostkey' in col_map and 'hostname' in col_map:
            host = {
                'hostkey': row[col_map['hostkey']],
                'hostname': row[col_map['hostname']],
                'ip': row[col_map['ipaddress']] if 'ipaddress' in col_map else '',
                'firstreport': row[col_map['firstreporttimestamp']] if 'firstreporttimestamp' in col_map else ''
            }
            if host['hostkey']:
                hosts.append(host)

    hosts_by_name = {}
    for host in hosts:
        hostname = host['hostname']
        if hostname not in hosts_by_name:
            hosts_by_name[hostname] = []
        hosts_by_name[hostname].append(host)

    for hostname, entries in hosts_by_name.items():
        if len(entries) > 1:
            sorted_entries = sorted(
                entries,
                key=lambda x: x.get('firstreport', ''),
                reverse=True
            )

            current = sorted_entries[0]
            for stale in sorted_entries[1:]:
                print(f"{stale['hostkey']},{current['hostkey']},{hostname},{stale['ip']}")

except Exception:
    pass
PYSCRIPT

curl -s -k -u "$MP_USER:$MP_PASSWORD" \
  -X POST "$MP_URL/api/query" \
  -H "Content-Type: application/json" \
  -d '{"query":"SELECT * FROM hosts"}' 2>/dev/null | python3 "$PYTEMP"
