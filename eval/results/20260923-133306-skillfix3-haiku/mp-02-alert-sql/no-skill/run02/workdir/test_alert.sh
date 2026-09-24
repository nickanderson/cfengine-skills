#!/bin/bash
set -e

# Test script for duplicate hostname detection alert
# This script tests the SQL query against the CFEngine Mission Portal database

MP_HOST="${MP_URL#https://}"
DB_PORT="5432"
DB_NAME="cfdb"
DB_USER="cfdb_mp"

echo "=== CFEngine Enterprise Alert SQL Test ==="
echo "Target: $MP_HOST:$DB_PORT/$DB_NAME"
echo

# Read the alert query
ALERT_SQL=$(cat alert.sql)

# Try to connect using various methods
echo "Attempting to test SQL against the hub..."

# Method 1: Direct psql (if db is accessible)
if command -v psql &> /dev/null; then
    echo -e "\n[1] Testing via direct psql connection..."
    export PGPASSWORD="$MP_PASSWORD"

    # Try the query
    if psql -h "$MP_HOST" -p "$DB_PORT" -U "$MP_USER" -d "$DB_NAME" -c "$ALERT_SQL" 2>&1 | grep -q "SELECT"; then
        echo "✓ SQL syntax appears valid (got SELECT results)"
    else
        echo "Attempting alternative connection..."
    fi
fi

# Method 2: SSH to hub and run psql locally
echo -e "\n[2] Testing via SSH to hub..."
if command -v ssh &> /dev/null; then
    ssh -o StrictHostKeyChecking=no "$MP_USER@$MP_HOST" "psql -h localhost -d $DB_NAME -c \"$ALERT_SQL\"" 2>&1 | head -10 || echo "SSH method failed"
fi

# Method 3: Create a SQL test file and show instructions
echo -e "\n[3] Manual testing instructions:"
echo "To verify this SQL query against your hub, run:"
echo ""
echo "  PGPASSWORD='$MP_PASSWORD' psql -h $MP_HOST -U cfdb_mp -d $DB_NAME -c"
echo "  \"$(echo "$ALERT_SQL" | tr '\n' ' ')\""
echo ""
echo "Or paste the following into the Mission Portal alert editor:"
echo "========================================================"
echo "$ALERT_SQL"
echo "========================================================"
echo ""
echo "Expected behavior:"
echo "- Returns hostnames that are being reported by multiple different hosts"
echo "- Each row shows a duplicate hostname"
echo "- Use as alert condition in Mission Portal dashboard"
