#!/usr/bin/env python3
import os
import glob
import json
from datetime import datetime

print("[*] Looking for CFEngine hub status/log files...")

# Look for host status files or databases
search_paths = [
    '/var/cfengine/state/**',
    '/var/cfengine/reports/**',
    '/var/cfengine/ppkeys/**',
    '/var/cfengine/lib/**',
]

for pattern in search_paths:
    matches = glob.glob(pattern, recursive=True)
    if matches:
        print(f"\n[*] Files matching {pattern}:")
        for f in matches[:10]:
            if os.path.isfile(f):
                try:
                    stat = os.stat(f)
                    size = stat.st_size
                    mtime = datetime.fromtimestamp(stat.st_mtime)
                    print(f"  {f} ({size} bytes, modified {mtime})")
                except:
                    pass

# Try to find any SQL database or data files
print("\n[*] Looking for database connection info...")
config_files = [
    '/etc/cfengine/cfmpd.conf',
    '/var/cfengine/httpd/var/cfmp.conf',
    '/var/cfengine/cfmp.conf',
    '/var/cfengine/missional_portal.conf',
]

for conf_file in config_files:
    if os.path.exists(conf_file):
        print(f"\n[*] Found config file: {conf_file}")
        with open(conf_file, 'r') as f:
            print(f.read()[:500])

