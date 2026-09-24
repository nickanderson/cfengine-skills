#!/usr/bin/env python3
import json
import os
import requests
import subprocess
from datetime import datetime

import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

mp_url = os.environ.get('MP_URL')
mp_user = os.environ.get('MP_USER')
mp_password = os.environ.get('MP_PASSWORD')

session = requests.Session()
session.auth = (mp_user, mp_password)
session.verify = False

# First, get basic API info
print("=== API Info ===")
response = session.get(f"{mp_url}/api", timeout=5)
if response.status_code == 200:
    data = response.json()
    print(json.dumps(data, indent=2))
    if 'data' in data and data['data']:
        api_info = data['data'][0]
        print(f"\nAPI Version: {api_info.get('apiVersion')}")
        print(f"Enterprise Version: {api_info.get('enterpriseVersion')}")
        print(f"Hub: {api_info.get('hub')}")

# Try to find other endpoints by checking common REST patterns
print("\n=== Trying common endpoints ===")
common_paths = [
    '/api/host',
    '/api/hosts',
    '/api/host/192.168.56.3',
    '/api/host/192.168.56.3/reports',
    '/api/host/192.168.56.3/status',
]

for path in common_paths:
    try:
        response = session.get(f"{mp_url}{path}", timeout=5)
        print(f"{path}: {response.status_code}")
        if response.status_code < 400:
            print(f"  {response.json()}")
    except Exception as e:
        print(f"{path}: {e}")

# Check if there's a graphql endpoint
print("\n=== Trying GraphQL ===")
try:
    response = session.get(f"{mp_url}/graphql", timeout=5)
    print(f"/graphql: {response.status_code}")
except Exception as e:
    print(f"/graphql: {e}")

# Try to use cf-runagent or other CFEngine tools if available
print("\n=== Checking for CFEngine tools ===")
try:
    result = subprocess.run(['which', 'cf-runagent'], capture_output=True, text=True)
    print(f"cf-runagent: {result.stdout.strip() if result.returncode == 0 else 'not found'}")
except:
    pass

try:
    result = subprocess.run(['which', 'cf-hub'], capture_output=True, text=True)
    print(f"cf-hub: {result.stdout.strip() if result.returncode == 0 else 'not found'}")
except:
    pass

try:
    result = subprocess.run(['which', 'cf-query'], capture_output=True, text=True)
    print(f"cf-query: {result.stdout.strip() if result.returncode == 0 else 'not found'}")
except:
    pass
