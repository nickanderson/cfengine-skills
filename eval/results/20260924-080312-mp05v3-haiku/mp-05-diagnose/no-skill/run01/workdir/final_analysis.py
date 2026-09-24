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

# Get API metadata
response = session.get(f"{mp_url}/api", timeout=5)
api_data = response.json()
api_info = api_data['data'][0] if api_data.get('data') else {}
current_timestamp = api_data['meta']['timestamp']  # Use meta timestamp

print(f"API timestamp: {current_timestamp}")
current_dt = datetime.utcfromtimestamp(current_timestamp)
print(f"Current time: {current_dt.isoformat()}Z")

# Get all hosts
response = session.get(f"{mp_url}/api/host", timeout=5)
hosts = response.json().get('data', [])

print(f"\n=== All hosts data ===")
for host in hosts:
    lastreport = int(host.get('lastreport', 0))
    lastreport_dt = datetime.utcfromtimestamp(lastreport)
    age_seconds = current_timestamp - lastreport if lastreport else None
    age_str = f"{age_seconds/60:.0f} min ago" if age_seconds else "unknown"
    print(f"{host['hostname']:20s} {host['ip']:15s} {host['id'][:15]}... {lastreport_dt.isoformat()}Z ({age_str})")

# Check for host002 in current reports
print(f"\n=== Checking for host002 (192.168.56.4) ===")
host002_found = False
for host in hosts:
    if host['ip'] == '192.168.56.4':
        host002_found = True
        print(f"Found: {host}")

if not host002_found:
    print(f"NOT in current host list")
    
    # Try to find in historical data
    # Check if there's any mention in other endpoints
    print(f"Checking for deleted hosts or historical data...")
    
    # Try some endpoints that might show deleted hosts
    endpoints = [
        '/api/host?deleted=true',
        '/api/host?filter=deleted',
        '/api/host?all=true',
        '/api/inventory',
    ]
    
    for endpoint in endpoints:
        try:
            resp = session.get(f"{mp_url}{endpoint}", timeout=5)
            if resp.status_code == 200:
                data = resp.json()
                print(f"  {endpoint}: {resp.status_code}")
                # Check if host002 is in the response
                resp_str = json.dumps(data)
                if '192.168.56.4' in resp_str or 'host002' in resp_str:
                    print(f"    Found host002 reference!")
                    print(f"    {data}")
        except Exception as e:
            pass

# Check for class information for host001
print(f"\n=== Looking for RBAC class for host001 ===")
host001_key = 'SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f'

# Check various endpoints for class/role info
endpoints = [
    f'/api/host/{quote(host001_key)}/classes',
    f'/api/host/{quote(host001_key)}/roles',
    f'/api/host/{quote(host001_key)}/acl',
    f'/api/host/{quote(host001_key)}/access',
    '/api/policy/host/classes',
    '/api/host/classes',
]

for endpoint in endpoints:
    try:
        resp = session.get(f"{mp_url}{endpoint}", timeout=5)
        if resp.status_code == 200:
            print(f"  {endpoint}: {resp.status_code}")
            print(f"    {json.dumps(resp.json(), indent=2)[:500]}")
    except:
        pass

# Try to check if we can query Mission Portal UI endpoints
print(f"\n=== Checking for UI/management endpoints ===")
endpoints = [
    '/api/host/classes',
    '/api/host-classes',
    '/api/rbac',
    '/api/access-control',
    '/api/policies',
]

for endpoint in endpoints:
    try:
        resp = session.get(f"{mp_url}{endpoint}", timeout=5)
        if resp.status_code < 400:
            print(f"  {endpoint}: {resp.status_code}")
    except:
        pass

# Based on what we know, make assumptions about Issue 1
print(f"\n=== ISSUE 1 ANALYSIS ===")
for host in hosts:
    if host['ip'] == '192.168.56.3':
        lastreport = int(host.get('lastreport', 0))
        lastreport_dt = datetime.utcfromtimestamp(lastreport)
        age_minutes = (current_timestamp - lastreport) / 60
        
        print(f"host001 last report: {lastreport_dt.isoformat()}Z")
        print(f"Age: {age_minutes:.1f} minutes")
        
        if age_minutes > 30:
            print("Status: Appears stale (>30 min)")
            print("The issue might be:")
            print("  - Agent not running on schedule (agent_not_running)")
            print("  - Hub not collecting from host (hub_not_collecting)")
        else:
            print("Status: Recent data")

# Check if we can differentiate between agent_not_running and hub_not_collecting
# We need last_agent_run vs last_collected
print(f"\n=== Trying to get last_agent_run vs last_collected ===")
response = session.get(f"{mp_url}/api/host?include=extended", timeout=5)
if response.status_code == 200:
    print("Extended host data available:")
    hosts_ext = response.json().get('data', [])
    for host in hosts_ext:
        if host['ip'] == '192.168.56.3':
            print(json.dumps(host, indent=2))
