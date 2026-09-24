#!/usr/bin/env python3
import json
import os
import requests
from urllib.parse import urljoin

import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

mp_url = os.environ.get('MP_URL')
mp_user = os.environ.get('MP_USER')
mp_password = os.environ.get('MP_PASSWORD')

session = requests.Session()
session.auth = (mp_user, mp_password)
session.verify = False

endpoints = [
    'api/hosts/',
    'api/hosts',
    'api/inventory/',
    'api/health/',
    'api/health',
    'api/system/',
    'api/roles/',
    'api/users/',
]

for endpoint in endpoints:
    url = urljoin(mp_url, endpoint)
    try:
        response = session.get(url, timeout=5)
        print(f"{endpoint}: {response.status_code}")
        if response.status_code < 400:
            try:
                data = response.json()
                print(f"  Keys: {list(data.keys()) if isinstance(data, dict) else 'list'}")
                if 'data' in data:
                    print(f"  Data count: {len(data['data'])}")
                    if data['data']:
                        print(f"  First item keys: {list(data['data'][0].keys())}")
            except:
                print(f"  Response: {response.text[:200]}")
    except Exception as e:
        print(f"{endpoint}: {e}")
