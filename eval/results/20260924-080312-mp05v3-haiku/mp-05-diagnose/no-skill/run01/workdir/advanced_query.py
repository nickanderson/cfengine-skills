#!/usr/bin/env python3
import json
import os
import requests
from datetime import datetime
from urllib.parse import quote

import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

mp_url = os.environ.get('MP_URL')
mp_user = os.environ.get('MP_USER')
mp_password = os.environ.get('MP_PASSWORD')

session = requests.Session()
session.auth = (mp_user, mp_password)
session.verify = False

def get_host_by_id(host_id):
    """Get detailed info for a host by ID"""
    endpoints = [
        f"/api/host/{quote(host_id)}",
        f"/api/host?id={quote(host_id)}",
    ]
    for endpoint in endpoints:
        try:
            response = session.get(f"{mp_url}{endpoint}", timeout=5)
            if response.status_code == 200:
                return response.json()
        except:
            pass
    return None

# Get all hosts first
response = session.get(f"{mp_url}/api/host", timeout=5)
hosts = response.json().get('data', [])

# Get details for each specific host we care about
hostkeys = {
    'host001': 'SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f',
    'host003': 'SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5',
    'hub': 'SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940',
}

print("=== Host Details ===")
for name, hostkey in hostkeys.items():
    print(f"\n{name} ({hostkey}):")
    details = get_host_by_id(hostkey)
    if details:
        print(json.dumps(details, indent=2))

# Check for deleted/stale hosts
print("\n=== Checking for host002 (192.168.56.4) ===")
# Try to find it any way
found_host002 = False
for host in hosts:
    if host['ip'] == '192.168.56.4':
        print(f"Found host002: {host}")
        found_host002 = True
if not found_host002:
    print("host002 not found in host list")

# Check for host003 (should be 192.168.56.5)
print("\n=== Checking for host003 (192.168.56.5) ===")
for host in hosts:
    if host['ip'] == '192.168.56.5':
        print(f"Found at 192.168.56.5: {host}")

# Try to access Health info through different endpoints
print("\n=== Trying to get Health/Status info ===")
endpoints = [
    '/api/health/status',
    '/api/status',
    '/api/report',
    '/api/reports',
    '/api/overview',
    '/api/dashboard',
]

for endpoint in endpoints:
    try:
        response = session.get(f"{mp_url}{endpoint}", timeout=5)
        if response.status_code < 400:
            print(f"\n{endpoint}: {response.status_code}")
            print(json.dumps(response.json(), indent=2))
    except:
        pass

# Try to get host-specific reports/status
print("\n=== Getting host execution status ===")
for host in hosts[:3]:  # Check first 3 hosts
    hostkey = host['id']
    print(f"\n{host['hostname']} ({hostkey}):")
    try:
        response = session.get(f"{mp_url}/api/host/{quote(hostkey)}/reports", timeout=5)
        print(f"  /reports: {response.status_code}")
    except:
        pass
    try:
        response = session.get(f"{mp_url}/api/host/{quote(hostkey)}/execution", timeout=5)
        print(f"  /execution: {response.status_code}")
    except:
        pass
    try:
        response = session.get(f"{mp_url}/api/host/{quote(hostkey)}/status", timeout=5)
        print(f"  /status: {response.status_code}")
    except:
        pass

# Check RBAC - can we see if alice has different view?
print("\n=== Checking RBAC for Alice ===")
# Switch to Alice's credentials
alice_session = requests.Session()
alice_session.auth = ('alice', os.environ.get('MP_PASSWORD'))
alice_session.verify = False

response = alice_session.get(f"{mp_url}/api/host", timeout=5)
if response.status_code == 200:
    alice_hosts = response.json().get('data', [])
    print(f"Alice sees {len(alice_hosts)} hosts:")
    for host in alice_hosts:
        print(f"  {host['hostname']} ({host['ip']})")
    
    print(f"\nDoes Alice see host001? ", end='')
    sees_host001 = any(h['ip'] == '192.168.56.3' for h in alice_hosts)
    print("YES" if sees_host001 else "NO")
