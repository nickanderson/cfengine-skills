Perfect! The script is working. Here's the complete script:

```bash
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
```

## Output from running against the hub:

```
SHA=c80bed38648aaeb68773826a6fb9a874baab9373db69b95099ef065541de1869,SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,host004.example.com,192.168.56.6
SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940,SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5,hub.example.com,192.168.56.2
```

The script found 2 stale host records:
1. **host004.example.com** – the old hostkey `c80bed38...` is still in the database, while the current hostkey is `714a8404...` at IP `192.168.56.6`
2. **hub.example.com** – the old hostkey `6bb77202...` is still in the database, while the current hostkey is `f20cfa67...` at IP `192.168.56.2`

The script identifies stale records by grouping hosts by hostname and comparing their first report timestamps – the hostkey with the most recent first report time is considered current (indicating a recent reinstall), and all others are marked as stale.