#!/usr/bin/env python3
import json
import os
import requests
from urllib.parse import quote

import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

mp_url = os.environ.get('MP_URL')
mp_user = os.environ.get('MP_USER')
mp_password = os.environ.get('MP_PASSWORD')

# Test Alice login
print("=== Testing Alice Login ===")
alice_session = requests.Session()
alice_session.auth = ('alice', mp_password)
alice_session.verify = False

response = alice_session.get(f"{mp_url}/api", timeout=5)
print(f"Alice login to /api: {response.status_code}")
if response.status_code == 200:
    data = response.json()
    print(f"Authenticated as: {data.get('data', [{}])[0].get('userId')}")

# Get host list as Alice
print("\n=== Hosts visible to Alice ===")
response = alice_session.get(f"{mp_url}/api/host", timeout=5)
print(f"Status: {response.status_code}")
if response.status_code == 200:
    hosts = response.json().get('data', [])
    print(f"Alice sees {len(hosts)} hosts:")
    for host in hosts:
        print(f"  {host['hostname']} ({host['ip']})")
    print(f"\nAlice sees host001? {'YES' if any(h['ip'] == '192.168.56.3' for h in hosts) else 'NO'}")
else:
    print(f"Error: {response.text}")

# Try to get host classes/attributes through different endpoints
print("\n=== Looking for class/attribute information ===")
admin_session = requests.Session()
admin_session.auth = (mp_user, mp_password)
admin_session.verify = False

endpoints = [
    '/api/host/SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f/classes',
    '/api/host/SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f/attributes',
    '/api/classes',
    '/api/attributes',
    '/api/variables',
    '/api/host/SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f/variables',
]

for endpoint in endpoints:
    try:
        response = admin_session.get(f"{mp_url}{endpoint}", timeout=5)
        print(f"{endpoint}: {response.status_code}")
        if response.status_code < 400:
            print(f"  {json.dumps(response.json(), indent=2)[:300]}")
    except:
        pass

# Check if we can find information about host002 through deleted hosts list
print("\n=== Looking for deleted/archived hosts ===")
endpoints = [
    '/api/host/deleted',
    '/api/host/archived',
    '/api/deleted',
    '/api/archived',
]

for endpoint in endpoints:
    try:
        response = admin_session.get(f"{mp_url}{endpoint}", timeout=5)
        print(f"{endpoint}: {response.status_code}")
        if response.status_code < 400:
            print(f"  {response.json()}")
    except:
        pass

# Try to get reports/execution history for host001
print("\n=== Looking for execution/report history endpoints ===")
endpoints = [
    '/api/host/SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f/lastexecution',
    '/api/host/SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f/lastreport',
    '/api/reports',
    '/api/last-report',
]

for endpoint in endpoints:
    try:
        response = admin_session.get(f"{mp_url}{endpoint}", timeout=5)
        print(f"{endpoint}: {response.status_code}")
        if response.status_code < 400:
            print(f"  {json.dumps(response.json(), indent=2)[:200]}")
    except:
        pass

# Look at roles and permissions structure
print("\n=== Checking roles/permissions ===")
endpoints = [
    '/api/roles',
    '/api/permissions',
    '/api/acl',
    '/api/access-control',
]

for endpoint in endpoints:
    try:
        response = admin_session.get(f"{mp_url}{endpoint}", timeout=5)
        print(f"{endpoint}: {response.status_code}")
        if response.status_code < 400:
            print(f"  {json.dumps(response.json(), indent=2)[:300]}")
    except:
        pass
