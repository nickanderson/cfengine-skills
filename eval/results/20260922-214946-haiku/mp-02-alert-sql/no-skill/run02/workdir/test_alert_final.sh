#!/bin/bash

MP_URL="${MP_URL}"
MP_USER="${MP_USER}"
MP_PASSWORD="${MP_PASSWORD}"

echo "Testing alert SQL against Mission Portal database..."
echo ""

# Create a JSON payload with proper escaping
python3 << 'PYTHON'
import json
import subprocess
import sys

mp_url = sys.argv[1]
mp_user = sys.argv[2]
mp_password = sys.argv[3]

sql_query = """SELECT hostname, COUNT(DISTINCT hostkey) as num_hosts
FROM hosts
WHERE hostname IS NOT NULL AND hostname != ''
GROUP BY hostname
HAVING COUNT(DISTINCT hostkey) > 1
ORDER BY num_hosts DESC, hostname;"""

payload = {
    "query": sql_query
}

# Execute the query via curl
cmd = [
    'curl', '-s', '-k',
    '-u', f'{mp_user}:{mp_password}',
    '-H', 'Content-Type: application/json',
    '-d', json.dumps(payload),
    f'{mp_url}/api/query'
]

result = subprocess.run(cmd, capture_output=True, text=True)
output = result.stdout

try:
    data = json.loads(output)
    if 'data' in data and len(data['data']) > 0:
        result_item = data['data'][0]
        print("✓ Query executed successfully!")
        print(f"  Query time: {result_item.get('queryTimeMs', 'N/A')}ms")
        print(f"  Rows returned: {result_item.get('rowCount', 0)}")
        
        if result_item.get('rowCount', 0) > 0:
            print("\n  Hosts with duplicate hostnames:")
            for row in result_item.get('rows', []):
                print(f"    Hostname: {row[0]}, Reported by {row[1]} different hosts")
        else:
            print("\n  No duplicate hostnames detected (alert would not trigger)")
    else:
        print("Query response structure unexpected:")
        print(json.dumps(data, indent=2))
except json.JSONDecodeError:
    print("Error parsing response:")
    print(output[:500])

PYTHON
