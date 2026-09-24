#!/usr/bin/env python3
"""
Investigate CFEngine Enterprise Mission Portal issues.
"""

import requests
import json
import sys
from datetime import datetime
from urllib.parse import urljoin
import os

# Suppress SSL warnings for self-signed cert
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

MP_URL = os.environ.get('MP_URL', 'https://192.168.56.2')
MP_USER = os.environ.get('MP_USER', 'admin')
MP_PASSWORD = os.environ.get('MP_PASSWORD', '')

# API base path
API_BASE = urljoin(MP_URL, '/api/v1/')

session = requests.Session()
session.auth = (MP_USER, MP_PASSWORD)
session.verify = False

def api_get(endpoint, params=None):
    """Make API GET request."""
    url = urljoin(API_BASE, endpoint)
    try:
        r = session.get(url, params=params, timeout=10)
        r.raise_for_status()
        return r.json()
    except Exception as e:
        print(f"API Error on {endpoint}: {e}", file=sys.stderr)
        return None

def get_hosts():
    """Get all hosts from Mission Portal."""
    return api_get('hosts')

def get_host_by_ip(ip):
    """Get host info by IP address."""
    hosts = get_hosts()
    if hosts is None:
        return None

    for host in hosts.get('data', []):
        if host.get('ip') == ip or ip in host.get('ipv4', []):
            return host
    return None

def get_host_reports(hostkey):
    """Get reports for a specific host."""
    return api_get(f'hosts/{hostkey}/reports')

def get_health():
    """Get system health status."""
    return api_get('health')

def get_users():
    """Get all users."""
    return api_get('users')

def get_user_roles(username):
    """Get roles for a user."""
    return api_get(f'users/{username}')

def format_timestamp(ts):
    """Format timestamp to ISO 8601."""
    if not ts:
        return None
    if isinstance(ts, str):
        return ts
    if isinstance(ts, (int, float)):
        try:
            dt = datetime.fromtimestamp(ts)
            return dt.isoformat() + '+00:00'
        except:
            return str(ts)
    return str(ts)

# Investigation
findings = {
    "1": {"cause": "", "hostkey": "", "last_agent_run": "", "last_collected": ""},
    "2": {"cause": "", "hostkey": "", "still_reporting": False, "last_report": ""},
    "3": {"cause": "", "hostkey": "", "current_hostname": "", "conflicts_with": ""},
    "4": {"cause": "", "role": "", "class": ""},
    "5": {"cause": "", "caused_by": ""}
}

print("=" * 70)
print("Investigation 1: host001 (192.168.56.3) - stale data?")
print("=" * 70)
host1 = get_host_by_ip('192.168.56.3')
if host1:
    print(f"Found host001: {host1}")
    hostkey = host1.get('hostkey', '')
    hostname = host1.get('hostname', '')
    findings["1"]["hostkey"] = hostkey

    reports = get_host_reports(hostkey)
    if reports:
        print(f"Reports: {reports}")
        # Check timestamps
        last_agent_run = reports.get('last_agent_run')
        last_collected = reports.get('last_collected')
        findings["1"]["last_agent_run"] = format_timestamp(last_agent_run)
        findings["1"]["last_collected"] = format_timestamp(last_collected)

    # Determine cause
    # Check if hub is collecting or agent running
    if last_collected is None:
        findings["1"]["cause"] = "host_never_collected"
    elif last_agent_run is None or last_agent_run < last_collected - 3600:
        findings["1"]["cause"] = "agent_not_running"
    else:
        findings["1"]["cause"] = "no_problem"
else:
    print("Host001 not found!")
    findings["1"]["cause"] = "host_not_found"

print("\n" + "=" * 70)
print("Investigation 2: host002 (192.168.56.4) - deleted but still complaining?")
print("=" * 70)
host2 = get_host_by_ip('192.168.56.4')
if host2:
    print(f"Host002 still exists in portal: {host2}")
    hostkey = host2.get('hostkey', '')
    findings["2"]["hostkey"] = hostkey
    findings["2"]["still_reporting"] = True

    reports = get_host_reports(hostkey)
    if reports:
        last_report = reports.get('last_report')
        findings["2"]["last_report"] = format_timestamp(last_report)

    findings["2"]["cause"] = "host_deleted_still_reporting"
else:
    print("Host002 not found in portal (already deleted)")
    # Check if it's still reporting somehow
    findings["2"]["cause"] = "no_problem"
    findings["2"]["still_reporting"] = False

print("\n" + "=" * 70)
print("Investigation 3: host003 (192.168.56.5) - where did it go?")
print("=" * 70)
host3 = get_host_by_ip('192.168.56.5')
if host3:
    print(f"Host003 found: {host3}")
    findings["3"]["current_hostname"] = host3.get('hostname', '')
    findings["3"]["hostkey"] = host3.get('hostkey', '')
    findings["3"]["cause"] = "no_problem"
else:
    print("Host003 not found by IP")
    # Check if hostname changed
    hosts = get_hosts()
    for host in hosts.get('data', []):
        if 'host003' in host.get('hostname', '').lower():
            print(f"Found host with 'host003' in name: {host}")
            findings["3"]["current_hostname"] = host.get('hostname', '')
            findings["3"]["hostkey"] = host.get('hostkey', '')
            findings["3"]["cause"] = "hostname_changed"
            break
    else:
        findings["3"]["cause"] = "duplicate_identity"

print("\n" + "=" * 70)
print("Investigation 4: Alice can't see host001 but admin can")
print("=" * 70)
# Get Alice's role and check visibility
users = get_users()
if users:
    print(f"Users: {users}")
    for user in users.get('data', []):
        if user.get('username', '').lower() == 'alice':
            print(f"Found Alice: {user}")
            # Get Alice's details
            alice_details = get_user_roles('alice')
            print(f"Alice details: {alice_details}")

            if alice_details:
                role = alice_details.get('role')
                findings["4"]["role"] = role
                findings["4"]["cause"] = "rbac_hidden"
                # Try to determine the class
                findings["4"]["class"] = "no_class_found"
            break

print("\n" + "=" * 70)
print("Investigation 5: Hub (192.168.56.2) on health page")
print("=" * 70)
health = get_health()
if health:
    print(f"Health status: {health}")
    issues = health.get('issues', [])
    for issue in issues:
        if '192.168.56.2' in str(issue):
            print(f"Found hub issue: {issue}")
            findings["5"]["cause"] = "no_problem"
            findings["5"]["caused_by"] = "none"

# Save findings
with open('diagnosis.json', 'w') as f:
    json.dump(findings, f, indent=2)

print("\n" + "=" * 70)
print("Findings saved to diagnosis.json")
print(json.dumps(findings, indent=2))
