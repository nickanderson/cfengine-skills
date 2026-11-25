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

# Try different API paths
endpoints = [
    'api/',
    'api/v1/',
    'api/v2/',
    'api/enterprise/',
    'api/hosts',
    'api/v1/hosts',
    'api/hosts/',
    'api/query',
]

for endpoint in endpoints:
    url = urljoin(mp_url, endpoint)
    try:
        response = session.get(url, timeout=5)
        print(f"{endpoint}: {response.status_code}")
        if response.status_code < 400:
            try:
                print(f"  Response: {response.json()}")
            except:
                print(f"  Response: {response.text[:500]}")
    except Exception as e:
        print(f"{endpoint}: {e}")
