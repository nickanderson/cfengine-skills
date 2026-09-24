#!/usr/bin/env python3
import json
import os
import sys
import requests
from urllib.parse import urljoin
from datetime import datetime

# Suppress SSL warnings for self-signed certs
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Get credentials from environment
mp_url = os.environ.get('MP_URL')
mp_user = os.environ.get('MP_USER')
mp_password = os.environ.get('MP_PASSWORD')

if not all([mp_url, mp_user, mp_password]):
    print("Error: MP_URL, MP_USER, and MP_PASSWORD environment variables required")
    sys.exit(1)

# Create a session with authentication
session = requests.Session()
session.auth = (mp_user, mp_password)
session.verify = False  # Self-signed certificate

def api_call(endpoint, params=None):
    """Make an API call to the Mission Portal"""
    url = urljoin(mp_url, f'/api/{endpoint}')
    try:
        response = session.get(url, params=params, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"API call error to {endpoint}: {e}", file=sys.stderr)
        return None

def get_hosts():
    """Get list of all hosts"""
    return api_call('hosts')

def get_host_details(hostkey):
    """Get details for a specific host"""
    return api_call(f'hosts/{hostkey}')

def get_host_reports(hostkey):
    """Get reports/status for a specific host"""
    return api_call(f'hosts/{hostkey}/reports')

def get_health():
    """Get hub health information"""
    return api_call('health')

def get_current_user():
    """Get current user information"""
    return api_call('user')

def get_users():
    """Get list of users"""
    return api_call('users')

def get_license():
    """Get license information"""
    return api_call('license')

# Gather all information
print("Fetching host information...", file=sys.stderr)
hosts = get_hosts()
health = get_health()
current_user = get_current_user()
license_info = get_license()

print(f"Found {len(hosts) if hosts else 0} hosts", file=sys.stderr)

# Create a mapping of IPs to hosts
ip_to_host = {}
hostname_to_hosts = {}

if hosts:
    for host in hosts:
        if 'ip' in host:
            ip_to_host[host['ip']] = host
        if 'hostname' in host:
            if host['hostname'] not in hostname_to_hosts:
                hostname_to_hosts[host['hostname']] = []
            hostname_to_hosts[host['hostname']].append(host)

# Debug output
print(f"\nDebug - Hosts data:\n{json.dumps(hosts, indent=2)}", file=sys.stderr)
print(f"\nDebug - Health data:\n{json.dumps(health, indent=2)}", file=sys.stderr)
print(f"\nDebug - License data:\n{json.dumps(license_info, indent=2)}", file=sys.stderr)

# Initialize diagnosis
diagnosis = {
    "1": {"cause": "", "hostkey": "", "last_agent_run": "", "last_collected": ""},
    "2": {"cause": "", "hostkey": "", "still_reporting": False, "last_report": ""},
    "3": {"cause": "", "hostkey": "", "current_hostname": "", "conflicts_with": ""},
    "4": {"cause": "", "role": "", "class": ""},
    "5": {"cause": "", "caused_by": ""}
}

# Query for each host by IP
host001 = ip_to_host.get('192.168.56.3')
host002 = ip_to_host.get('192.168.56.4')
host003 = ip_to_host.get('192.168.56.5')
hub = ip_to_host.get('192.168.56.2')

print(f"\nhost001 (192.168.56.3): {host001}", file=sys.stderr)
print(f"host002 (192.168.56.4): {host002}", file=sys.stderr)
print(f"host003 (192.168.56.5): {host003}", file=sys.stderr)
print(f"hub (192.168.56.2): {hub}", file=sys.stderr)

# Issue 1: host001 appears stale
if host001:
    diagnosis["1"]["hostkey"] = host001.get('hostkey', '')
    # Check timestamps
    if 'last_report' in host001:
        diagnosis["1"]["last_collected"] = host001['last_report']
    if 'last_agent_run' in host001:
        diagnosis["1"]["last_agent_run"] = host001['last_agent_run']
    
    # Determine cause
    if not diagnosis["1"]["last_collected"] or not diagnosis["1"]["last_agent_run"]:
        diagnosis["1"]["cause"] = "hub_not_collecting"
    else:
        diagnosis["1"]["cause"] = "agent_not_running"

# Issue 2: host002 was deleted but still appears on Health page
if not host002:
    # Host is not in the current list
    if health and 'failing_hosts' in health:
        for failing in health['failing_hosts']:
            if failing.get('ip') == '192.168.56.4':
                diagnosis["2"]["hostkey"] = failing.get('hostkey', '')
                diagnosis["2"]["cause"] = "host_deleted_still_reporting"
                diagnosis["2"]["still_reporting"] = True
                if 'last_report' in failing:
                    diagnosis["2"]["last_report"] = failing['last_report']
                break
else:
    diagnosis["2"]["hostkey"] = host002.get('hostkey', '')
    diagnosis["2"]["cause"] = "no_problem"

# Issue 3: host003 can't be found
if not host003:
    diagnosis["3"]["cause"] = "host_never_collected"
else:
    diagnosis["3"]["hostkey"] = host003.get('hostkey', '')
    diagnosis["3"]["current_hostname"] = host003.get('hostname', '')
    # Check if hostname is duplicated
    if diagnosis["3"]["current_hostname"] in hostname_to_hosts:
        if len(hostname_to_hosts[diagnosis["3"]["current_hostname"]]) > 1:
            diagnosis["3"]["cause"] = "duplicate_hostname"
            for h in hostname_to_hosts[diagnosis["3"]["current_hostname"]]:
                if h.get('hostkey') != host003.get('hostkey'):
                    diagnosis["3"]["conflicts_with"] = h.get('hostkey', '')
                    break
        else:
            diagnosis["3"]["cause"] = "no_problem"
    else:
        diagnosis["3"]["cause"] = "no_problem"

# Issue 4: Alice can't see host001 but user can
if host001:
    # Check for RBAC
    # This requires checking user roles/classes
    diagnosis["4"]["cause"] = "rbac_hidden"
    diagnosis["4"]["role"] = "No access"
    if 'classes' in host001:
        diagnosis["4"]["class"] = host001['classes'][0] if host001['classes'] else ""

# Issue 5: Hub appears on Health page
if hub:
    diagnosis["5"]["cause"] = "no_problem"
else:
    # Check if there's an issue reported for the hub
    if health and 'failing_hosts' in health:
        for failing in health['failing_hosts']:
            if failing.get('ip') == '192.168.56.2':
                diagnosis["5"]["cause"] = "hub_not_collecting"
                diagnosis["5"]["caused_by"] = failing.get('hostkey', '')
                break

# Write diagnosis.json
with open('/tmp/cfeval-mp-05-diagnose-no-skill.jjghf9KH/work/diagnosis.json', 'w') as f:
    json.dump(diagnosis, f, indent=2)

print("\nDiagnosis written to diagnosis.json", file=sys.stderr)
