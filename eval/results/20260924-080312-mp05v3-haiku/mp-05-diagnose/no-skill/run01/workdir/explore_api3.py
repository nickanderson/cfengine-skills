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

# Try without trailing slash, with parameters
endpoints = [
    ('api/inventory', None),
    ('api/inventory', {'page': 1}),
    ('api/hosts', None),
    ('api/hosts', {'query': 'hostname=host001'}),
    ('api/nodes', None),
    ('api/compliance', None),
    ('api/packages', None),
]

for endpoint, params in endpoints:
    try:
        url = f"{mp_url.rstrip('/')}/{endpoint}"
        response = session.get(url, params=params, timeout=5)
        print(f"{endpoint} {params}: {response.status_code}")
        if response.status_code < 400:
            try:
                data = response.json()
                print(f"  Response: {json.dumps(data, indent=2)[:500]}")
            except:
                print(f"  Response text: {response.text[:200]}")
    except Exception as e:
        print(f"{endpoint}: {e}")
