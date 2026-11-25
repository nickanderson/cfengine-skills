#!/bin/bash
# Look for Mission Portal schema documentation or files

echo "=== Looking for Mission Portal files ==="
find /var/cfengine -name "*.py" -type f 2>/dev/null | xargs grep -l "SELECT.*hostname" 2>/dev/null | head -5

echo -e "\n=== Searching for database migrations or schema files ==="
find /var/cfengine -name "*schema*" -o -name "*migration*" 2>/dev/null | head -10

echo -e "\n=== Checking CFEngine documentation ==="
find /var/cfengine -type f -name "*.md" -o -name "*.txt" 2>/dev/null | head -10
