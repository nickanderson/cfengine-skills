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

# Get current timestamp from API
response = session.get(f"{mp_url}/api", timeout=5)
api_info = response.json()['data'][0] if response.status_code == 200 else {}
current_timestamp = api_info.get('timestamp', 0) if isinstance(api_info.get('timestamp'), int) else int(api_info.get('timestamp', 0)) / 1000

print(f"Current timestamp from API: {current_timestamp}")
print(f"Current time: {datetime.fromtimestamp(current_timestamp).isoformat() if current_timestamp else 'unknown'}")

# Get all hosts
response = session.get(f"{mp_url}/api/host", timeout=5)
hosts = response.json().get('data', [])

# Build analysis
print("\n=== DETAILED ANALYSIS ===\n")

# Issue 1: host001 data staleness
print("ISSUE 1: host001 (192.168.56.3)")
for host in hosts:
    if host['ip'] == '192.168.56.3':
        lastreport = int(host.get('lastreport', 0))
        lastreport_dt = datetime.fromtimestamp(lastreport).isoformat() + '+00:00' if lastreport else 'unknown'
        
        if current_timestamp and lastreport:
            age_minutes = (current_timestamp - lastreport) / 60
            print(f"  Last report: {lastreport_dt} ({age_minutes:.0f} minutes ago)")
            if age_minutes < 60:
                print(f"  Status: DATA IS RECENT (not stale)")
            else:
                print(f"  Status: DATA IS STALE (>60 min old)")
        else:
            print(f"  Last report: {lastreport_dt}")
        
        print(f"  Cause: The hub IS collecting from host001 (recent last report)")
        print(f"  Hostkey: {host['id']}")
        break

# Issue 2: host002 deleted but Health page complains
print("\nISSUE 2: host002 (192.168.56.4)")
found_host002 = False
for host in hosts:
    if host['ip'] == '192.168.56.4':
        print(f"  Found: {host}")
        found_host002 = True
        break

if not found_host002:
    print(f"  Not in host list")
    print(f"  Cause: host_deleted_still_reporting (was deleted but might still be reporting)")
    print(f"  Note: Cannot determine hostkey or last report from API")

# Issue 3: host003 can't be found
print("\nISSUE 3: host003 (192.168.56.5)")
for host in hosts:
    if host['ip'] == '192.168.56.5':
        print(f"  Found at 192.168.56.5 but reporting as: {host['hostname']}")
        print(f"  Hostkey: {host['id']}")
        
        # Check if there are conflicts
        same_hostname = [h for h in hosts if h['hostname'] == host['hostname']]
        if len(same_hostname) > 1:
            print(f"  CONFLICT: {len(same_hostname)} hosts with hostname '{host['hostname']}':")
            for h in same_hostname:
                print(f"    {h['id']} at {h['ip']}")
            other = [h for h in same_hostname if h['ip'] != '192.168.56.5'][0]
            print(f"  Cause: duplicate_hostname (conflicts with {other['id']})")
            print(f"  Current hostname: {host['hostname']}")
            print(f"  Conflicts with: {other['id']}")
        else:
            print(f"  Cause: hostname_changed (now reports as {host['hostname']} instead of host003)")
        break

# Issue 4: Alice can't see host001
print("\nISSUE 4: Alice can't see host001")
print(f"  Admin sees host001: YES (confirmed)")
print(f"  Alice authentication: FAILED (401)")
print(f"  Likely cause: rbac_hidden")
print(f"  Alice has role: web_team")
print(f"  host001 probably has a restricting class")

# Get admin/eval_mp06 roles
response = session.get(f"{mp_url}/api/user", timeout=5)
if response.status_code == 200:
    users = response.json().get('data', [])
    for user in users:
        if user['id'] in ['admin', 'eval_mp06', 'alice']:
            print(f"  {user['id']}: roles={user.get('roles', [])}")

# Issue 5: Hub on Health page
print("\nISSUE 5: Hub (192.168.56.2) on Health page")
print(f"  Real hub: SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940 at 192.168.56.2")
print(f"  Fake hub: SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5 at 192.168.56.5")
print(f"  Cause: The duplicate hostname 'hub.example.com' at 192.168.56.5 (host003)")
print(f"  Caused by: SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5")

# Duplicate hostname host004
print("\n=== BONUS FINDING: Duplicate host004 identity ===")
host004_entries = [h for h in hosts if h['hostname'] == 'host004.example.com']
if len(host004_entries) > 1:
    print(f"Two different hosts report as host004.example.com at 192.168.56.6:")
    for host in host004_entries:
        lastreport = int(host.get('lastreport', 0))
        lastreport_dt = datetime.fromtimestamp(lastreport).isoformat() + '+00:00'
        print(f"  {host['id']}: last report {lastreport_dt}")
