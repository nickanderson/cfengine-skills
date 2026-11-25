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

def get_all_hosts():
    """Get all hosts from the API"""
    response = session.get(f"{mp_url}/api/host", timeout=5)
    if response.status_code == 200:
        return response.json()
    return None

def get_host_status(hostkey):
    """Get detailed status for a host"""
    encoded_key = quote(hostkey)
    endpoints = [
        f"/api/host/{encoded_key}",
        f"/api/host?id={encoded_key}",
    ]
    for endpoint in endpoints:
        try:
            response = session.get(f"{mp_url}{endpoint}", timeout=5)
            if response.status_code == 200:
                return response.json()
        except:
            pass
    return None

def query_graphql(query_str):
    """Query using GraphQL"""
    try:
        response = session.post(f"{mp_url}/graphql", 
                               json={"query": query_str}, 
                               timeout=10)
        if response.status_code == 200:
            return response.json()
    except Exception as e:
        print(f"GraphQL error: {e}")
    return None

# Get all hosts
print("=== All Hosts ===")
hosts_data = get_all_hosts()
if hosts_data:
    hosts = hosts_data.get('data', [])
    print(f"Found {len(hosts)} hosts:")
    for host in hosts:
        lastreport = int(host.get('lastreport', 0))
        timestamp = datetime.fromtimestamp(lastreport).isoformat() + '+00:00' if lastreport else 'unknown'
        print(f"  {host['hostname']} ({host['ip']}): id={host['id']}, firstseen={host['firstseen']}, lastreport={timestamp}")

# Try GraphQL query for more details
print("\n=== GraphQL Query ===")
graphql_query = """
{
  hosts {
    id
    hostname
    ip
    lastreport
    lastexecution
    agentStatus
    policyStatus
  }
}
"""
graphql_result = query_graphql(graphql_query)
if graphql_result:
    print(json.dumps(graphql_result, indent=2))
else:
    print("GraphQL query failed or returned no data")

# Try querying for specific host info
print("\n=== Querying specific hosts ===")
ips = ['192.168.56.2', '192.168.56.3', '192.168.56.4', '192.168.56.5', '192.168.56.6']
for ip in ips:
    response = session.get(f"{mp_url}/api/host?ip={ip}", timeout=5)
    if response.status_code == 200:
        data = response.json()
        if data.get('data'):
            print(f"\n{ip}:")
            for host in data['data']:
                print(f"  {host}")

# Check health/reporting status
print("\n=== Health Status ===")
health_endpoints = [
    '/api/health',
    '/api/reporting',
    '/api/hosts/status',
]
for endpoint in health_endpoints:
    try:
        response = session.get(f"{mp_url}{endpoint}", timeout=5)
        print(f"{endpoint}: {response.status_code}")
        if response.status_code < 400:
            print(f"  {response.json()}")
    except Exception as e:
        print(f"{endpoint}: {e}")

# Query users and their roles
print("\n=== Users and Roles ===")
try:
    response = session.get(f"{mp_url}/api/user", timeout=5)
    print(f"/api/user: {response.status_code}")
    if response.status_code == 200:
        print(json.dumps(response.json(), indent=2))
except Exception as e:
    print(f"/api/user: {e}")

try:
    response = session.get(f"{mp_url}/api/users", timeout=5)
    print(f"/api/users: {response.status_code}")
    if response.status_code == 200:
        print(json.dumps(response.json(), indent=2))
except Exception as e:
    print(f"/api/users: {e}")
