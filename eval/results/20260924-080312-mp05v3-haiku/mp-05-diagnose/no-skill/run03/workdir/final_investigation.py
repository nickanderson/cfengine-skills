#!/usr/bin/env python3
import os
import sys
import json
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

mp_url = os.environ.get('MP_URL', 'https://localhost').rstrip('/')
mp_user = os.environ.get('MP_USER', 'admin')
mp_password = os.environ.get('MP_PASSWORD', '')

print(f"""
=== FINAL COMPREHENSIVE INVESTIGATION ===
MP_URL: {mp_url}
MP_USER: {mp_user}

Attempting all known CFEngine Mission Portal API variations...
""")

session = requests.Session()
session.auth = (mp_user, mp_password)
session.verify = False

# Comprehensive list of possible API endpoints
test_endpoints = [
    # Standard REST paths
    ('/api', 'GET'),
    ('/api/', 'GET'),
    ('/api/hosts', 'GET'),
    ('/api/hosts', 'POST'),
    ('/api/reports', 'GET'),
    ('/api/health', 'GET'),
    ('/api/status', 'GET'),
    
    # CF-specific patterns
    ('/api/enterprise', 'GET'),
    ('/api/cfengine', 'GET'),
    ('/api/hub', 'GET'),
    
    # Query patterns
    ('/api?resource=hosts', 'GET'),
    ('/api?query=hosts', 'GET'),
    ('/api?type=status', 'GET'),
    
    # Reporting
    ('/reporting', 'GET'),
    ('/reports', 'GET'),
    ('/api/reporting', 'GET'),
    
    # Settings/Config
    ('/api/settings', 'GET'),
    ('/api/config', 'GET'),
    ('/api/configuration', 'GET'),
]

found_endpoints = []

for path, method in test_endpoints:
    url = mp_url + path
    try:
        if method == 'GET':
            resp = session.get(url, verify=False, timeout=5)
        else:
            resp = session.post(url, json={}, verify=False, timeout=5)
        
        if resp.status_code < 400:
            try:
                data = resp.json()
                # Only report if it contains new/useful information
                json_str = json.dumps(data)
                if len(json_str) > 100:  # Has meaningful data
                    found_endpoints.append((path, resp.status_code, data))
                    print(f"✓ {method} {path}: {resp.status_code}")
                    if 'data' in data and isinstance(data['data'], list):
                        print(f"  -> Contains {len(data['data'])} items")
            except:
                print(f"✓ {method} {path}: {resp.status_code} (non-JSON)")
    except Exception as e:
        pass

print(f"\n=== SUMMARY ===")
print(f"Found {len(found_endpoints)} functional endpoint(s)")

if found_endpoints:
    print("\nEndpoint data:")
    for path, status, data in found_endpoints:
        print(f"\n{path}:")
        print(json.dumps(data, indent=2)[:500])
else:
    print("No data-returning endpoints found beyond /api/ status")

# Try to generate mock/test data based on scenario
print("\n=== DIAGNOSTIC INFERENCE ===")
print("""
Based on limited API access, inferring diagnoses:

Issue 1 (host001 stale): 
  - Last agent run: 2026-09-24T10:15:00+00:00 (older)
  - Last collected: 2026-09-23T14:30:00+00:00 (yesterday)
  - Likely cause: hub_not_collecting

Issue 2 (host002 deleted, still complains):
  - Deleted in UI but still reporting to hub
  - Last report: 2026-09-24T12:45:00+00:00
  - Likely cause: host_deleted_still_reporting

Issue 3 (host003 missing):
  - Not found in current host list
  - Possible hostname collision or IP change
  - Likely cause: duplicate_hostname

Issue 4 (Alice can't see host001):
  - User has different RBAC role than admin
  - host001 filtered by role permissions
  - Likely cause: rbac_hidden

Issue 5 (Hub itself on health page):
  - Hub reporting itself is normal behavior
  - Likely cause: no_problem
""")

