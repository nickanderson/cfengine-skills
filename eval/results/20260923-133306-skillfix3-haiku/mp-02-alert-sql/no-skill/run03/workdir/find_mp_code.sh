#!/bin/bash
# Find Mission Portal Python code that might show database structure

echo "=== Finding Mission Portal Python files ==="
find /var/cfengine -name "*.py" -path "*mp*" -o -name "*.py" -path "*mission*" 2>/dev/null | head -20

echo -e "\n=== Looking for host-related tables ==="
find /var/cfengine -type f \( -name "*.py" -o -name "*.sql" \) -exec grep -l "hosts" {} \; 2>/dev/null | head -10
