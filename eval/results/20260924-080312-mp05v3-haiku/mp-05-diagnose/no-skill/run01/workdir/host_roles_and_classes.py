#!/usr/bin/env python3
import json
import os
import requests
from datetime import datetime

import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

mp_url = os.environ.get('MP_URL')
mp_user = os.environ.get('MP_USER')
mp_password = os.environ.get('MP_PASSWORD')

session = requests.Session()
session.auth = (mp_user, mp_password)
session.verify = False

# Check role-based permissions for hosts
print("=== Looking for role-based host access control ===")

# Try endpoints that might map roles to host visibility
endpoints = [
    '/api/rbac/roles',
    '/api/rbac/permissions',
    '/api/role',
    '/api/roles',
    '/api/permissions',
    '/api/access',
    '/api/roles/web_team',
    '/api/role/admin',
]

for endpoint in endpoints:
    try:
        resp = session.get(f"{mp_url}{endpoint}", timeout=5)
        if resp.status_code == 200:
            print(f"\n{endpoint}: {resp.status_code}")
            data = resp.json()
            # Print first 500 chars
            print(json.dumps(data, indent=2)[:500])
    except:
        pass

# Check if there's a mapping of roles to classes
print("\n=== Checking user role details ===")
resp = session.get(f"{mp_url}/api/user", timeout=5)
if resp.status_code == 200:
    users = resp.json().get('data', [])
    for user in users:
        if user['id'] == 'alice':
            print(f"Alice: {json.dumps(user, indent=2)}")

# Try to find policies or bundles that might define class access
print("\n=== Checking for policy/bundle information ===")
endpoints = [
    '/api/policy',
    '/api/policies',
    '/api/bundles',
    '/api/bundle',
]

for endpoint in endpoints:
    try:
        resp = session.get(f"{mp_url}{endpoint}", timeout=5)
        if resp.status_code == 200:
            print(f"\n{endpoint}: {resp.status_code}")
    except:
        pass

# Look for host002 in any way
print("\n=== Final search for host002 ===")
# Try various queries
queries = [
    ('', {}),
    ('', {'search': '192.168.56.4'}),
    ('', {'ip': '192.168.56.4'}),
    ('', {'hostname': 'host002'}),
    ('', {'deleted': '1'}),
]

for endpoint, params in queries:
    try:
        resp = session.get(f"{mp_url}/api/host", params=params, timeout=5)
        if resp.status_code == 200:
            data = resp.json()
            hosts = data.get('data', [])
            for host in hosts:
                if '192.168.56.4' in str(host.get('ip', '')) or 'host002' in str(host.get('hostname', '')):
                    print(f"\nFOUND host002 with params={params}:")
                    print(json.dumps(host, indent=2))
    except:
        pass

# Check inventory endpoint to see if it has more details
print("\n=== Checking /api/inventory ===")
try:
    resp = session.get(f"{mp_url}/api/inventory", timeout=5)
    if resp.status_code == 200:
        print(f"Status: {resp.status_code}")
        data = resp.json()
        print(f"Keys: {list(data.keys())}")
        # Check for host002
        for host_data in data.get('data', []):
            if '192.168.56.4' in str(host_data) or 'host002' in str(host_data):
                print(f"Found host002: {host_data}")
except Exception as e:
    print(f"Error: {e}")

# Check for any references to "still_reporting" concept
print("\n=== Checking unreachable/stale hosts ===")
endpoints = [
    '/api/host/unreachable',
    '/api/unreachable',
    '/api/stale',
    '/api/host/stale',
]

for endpoint in endpoints:
    try:
        resp = session.get(f"{mp_url}{endpoint}", timeout=5)
        if resp.status_code < 400:
            print(f"{endpoint}: {resp.status_code}")
            print(json.dumps(resp.json(), indent=2)[:300])
    except:
        pass
