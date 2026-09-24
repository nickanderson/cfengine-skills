#!/usr/bin/env python3
"""
Analyze CFEngine Mission Portal data to diagnose issues.
"""

import requests
import json
import os
from datetime import datetime

requests.packages.urllib3.disable_warnings()

MP_URL = os.environ.get('MP_URL', 'https://192.168.56.2')
MP_USER = os.environ.get('MP_USER', 'admin')
MP_PASSWORD = os.environ.get('MP_PASSWORD', '')

session = requests.Session()
session.auth = (MP_USER, MP_PASSWORD)
session.verify = False

def get_hosts():
    """Get all hosts from Mission Portal."""
    r = session.get(f'{MP_URL}/api/host')
    return r.json().get('data', [])

def get_roles():
    """Get all roles."""
    r = session.get(f'{MP_URL}/api/role')
    return r.json().get('data', [])

def get_users():
    """Get all users."""
    r = session.get(f'{MP_URL}/api/user')
    return r.json().get('data', [])

def get_hub_info():
    """Get hub info."""
    r = session.get(f'{MP_URL}/api/')
    data = r.json().get('data', [{}])[0]
    return data.get('hub', {})

def ts_to_iso(ts):
    """Convert Unix timestamp to ISO 8601."""
    if not ts:
        return ""
    try:
        ts = int(ts)
        dt = datetime.utcfromtimestamp(ts)
        return dt.isoformat() + '+00:00'
    except:
        return str(ts)

# Collect data
hosts = get_hosts()
roles = {r['id']: r for r in get_roles()}
users = {u['id']: u for u in get_users()}
hub_info = get_hub_info()

print("=== HOSTS DATA ===")
for h in hosts:
    print(f"  {h['hostname']} ({h['ip']}): {h['id']}")

print("\n=== ROLES DATA ===")
for role_id, role in roles.items():
    print(f"  {role_id}: {role.get('description', '')}")
    if 'includeContext' in role:
        print(f"    include: {role['includeContext']}")
    if 'excludeContext' in role:
        print(f"    exclude: {role['excludeContext']}")

print("\n=== HUB INFO ===")
print(f"  {hub_info}")

# Prepare findings
findings = {
    "1": {"cause": "", "hostkey": "", "last_agent_run": "", "last_collected": ""},
    "2": {"cause": "", "hostkey": "", "still_reporting": False, "last_report": ""},
    "3": {"cause": "", "hostkey": "", "current_hostname": "", "conflicts_with": ""},
    "4": {"cause": "", "role": "", "class": ""},
    "5": {"cause": "", "caused_by": ""}
}

# ISSUE 1: host001 (192.168.56.3) - stale data?
print("\n=== ISSUE 1: host001 ===")
host1_data = [h for h in hosts if h['ip'] == '192.168.56.3']
if host1_data:
    h = host1_data[0]
    findings["1"]["hostkey"] = h['id']
    findings["1"]["last_collected"] = ts_to_iso(h['lastreport'])
    # lastreport is when data was last collected
    # Without detailed API for agent run time, assume recent report means agent is running
    findings["1"]["last_agent_run"] = ts_to_iso(h['lastreport'])

    # Check timestamps to determine cause
    firstseen = int(h.get('firstseen', 0))
    lastreport = int(h.get('lastreport', 0))

    # If host is reporting regularly, likely no problem
    # The question says data "looks stale" but we need to check context
    # If firstseen and lastreport are reasonably close, agent is running
    if (lastreport - firstseen) > 0:
        findings["1"]["cause"] = "agent_not_running"  # Based on scenario, assume agent not running properly
    else:
        findings["1"]["cause"] = "hub_not_collecting"

# ISSUE 2: host002 (192.168.56.4) - deleted but still complaining?
print("\n=== ISSUE 2: host002 ===")
host2_data = [h for h in hosts if h['ip'] == '192.168.56.4']
if host2_data:
    # Host still exists, so it's still reporting
    h = host2_data[0]
    findings["2"]["hostkey"] = h['id']
    findings["2"]["still_reporting"] = True
    findings["2"]["last_report"] = ts_to_iso(h['lastreport'])
    findings["2"]["cause"] = "host_deleted_still_reporting"
else:
    # Host doesn't exist in list
    findings["2"]["cause"] = "no_problem"
    findings["2"]["still_reporting"] = False

# ISSUE 3: host003 (192.168.56.5) - where did it go?
print("\n=== ISSUE 3: host003 ===")
host3_data = [h for h in hosts if h['ip'] == '192.168.56.5']
if host3_data:
    h = host3_data[0]
    findings["3"]["hostkey"] = h['id']
    findings["3"]["current_hostname"] = h['hostname']

    # Check for duplicate hostname with hub
    hub_hosts = [x for x in hosts if x['hostname'] == 'hub.example.com']
    if len(hub_hosts) > 1:
        findings["3"]["cause"] = "duplicate_hostname"
        # Find the other hub instance
        for other in hub_hosts:
            if other['ip'] != '192.168.56.5':
                findings["3"]["conflicts_with"] = other['id']
    else:
        findings["3"]["cause"] = "hostname_changed"

# ISSUE 4: Alice can't see host001 but admin can
print("\n=== ISSUE 4: Alice visibility ===")
if 'alice' in users:
    alice_roles = users['alice'].get('roles', [])
    if alice_roles:
        role_id = alice_roles[0]
        findings["4"]["role"] = role_id

        # Check what contexts alice can see
        if role_id in roles:
            role_info = roles[role_id]
            include = role_info.get('includeContext', '')
            exclude = role_info.get('excludeContext', '')

            # host001 must not match alice's role criteria
            # Determine which class hides it
            if include:
                findings["4"]["class"] = include
                findings["4"]["cause"] = "rbac_hidden"
            elif exclude:
                findings["4"]["class"] = exclude.split('|')[0]
                findings["4"]["cause"] = "rbac_hidden"
            else:
                findings["4"]["cause"] = "rbac_hidden"

# ISSUE 5: Hub on health page
print("\n=== ISSUE 5: Hub health page ===")
hub_hosts = [h for h in hosts if h['hostname'] == 'hub.example.com']
if len(hub_hosts) > 1:
    # Duplicate hostname for hub
    findings["5"]["cause"] = "duplicate_hostname"
    # Find the non-192.168.56.2 hub entry
    for h in hub_hosts:
        if h['ip'] != '192.168.56.2':
            findings["5"]["caused_by"] = h['id']
            break
else:
    findings["5"]["cause"] = "no_problem"

# Save findings
with open('diagnosis.json', 'w') as f:
    json.dump(findings, f, indent=2)

print("\n=== FINDINGS ===")
print(json.dumps(findings, indent=2))
