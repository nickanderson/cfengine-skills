#!/usr/bin/env python3
import json
import os
import requests

import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

mp_url = os.environ.get('MP_URL')
mp_user = os.environ.get('MP_USER')
mp_password = os.environ.get('MP_PASSWORD')

session = requests.Session()
session.auth = (mp_user, mp_password)
session.verify = False

print("=== Looking for deleted hosts ===")
response = session.get(f"{mp_url}/api/host?deleted=true", timeout=5)
if response.status_code == 200:
    data = response.json()
    print(f"Status: {response.status_code}")
    print(f"Deleted hosts: {len(data.get('data', []))}")
    for host in data.get('data', []):
        print(f"  {host['hostname']} at {host['ip']}: {host['id']}, last report: {host.get('lastreport')}")
        if '192.168.56.4' in host['ip'] or 'host002' in host['hostname']:
            print(f"    ^^^ FOUND host002!")

print("\n=== Looking with filter=deleted ===")
response = session.get(f"{mp_url}/api/host?filter=deleted", timeout=5)
if response.status_code == 200:
    data = response.json()
    print(f"Status: {response.status_code}")
    hosts = data.get('data', [])
    print(f"Hosts matching deleted filter: {len(hosts)}")
    for host in hosts:
        print(f"  {host.get('hostname')} at {host.get('ip')}")

print("\n=== Looking with all=true ===")
response = session.get(f"{mp_url}/api/host?all=true", timeout=5)
if response.status_code == 200:
    data = response.json()
    print(f"Status: {response.status_code}")
    hosts = data.get('data', [])
    print(f"All hosts (including deleted?): {len(hosts)}")
    for host in hosts:
        lastreport = host.get('lastreport', '?')
        print(f"  {host.get('hostname'):20s} at {host.get('ip'):15s} key={host['id'][:15]}... report={lastreport}")
        if '192.168.56.4' in str(host.get('ip', '')):
            print(f"    ^^^ FOUND host002 at 192.168.56.4!")
            print(f"    Full entry: {host}")

print("\n=== Checking RBAC ===")
response = session.get(f"{mp_url}/api/rbac", timeout=5)
if response.status_code == 200:
    rbac_data = response.json()
    print(f"Status: {response.status_code}")
    print(json.dumps(rbac_data, indent=2)[:1000])

print("\n=== Checking for role-based classes ===")
response = session.get(f"{mp_url}/api/rbac/roles", timeout=5)
if response.status_code == 200:
    print(f"/api/rbac/roles: {response.status_code}")
    print(json.dumps(response.json(), indent=2))

response = session.get(f"{mp_url}/api/rbac/host", timeout=5)
if response.status_code == 200:
    print(f"\n/api/rbac/host: {response.status_code}")
    print(json.dumps(response.json(), indent=2)[:1000])
