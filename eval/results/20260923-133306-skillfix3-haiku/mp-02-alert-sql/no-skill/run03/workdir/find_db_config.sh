#!/bin/bash
# Look for database configuration in common locations

echo "=== Checking for PostgreSQL configuration ==="
sudo -n find /var/cfengine -name "*.conf" 2>/dev/null | grep -i db | head -10
sudo -n find /etc/postgresql -name "*.conf" 2>/dev/null | head -10

echo -e "\n=== Checking for Mission Portal config ==="
sudo -n find /var/cfengine -name "config.sh" -o -name "settings.py" 2>/dev/null | head -10

echo -e "\n=== Checking pg_hba.conf for access rules ==="
sudo -n cat /etc/postgresql/*/main/pg_hba.conf 2>/dev/null | grep -v "^#" | grep -v "^$" | head -20
