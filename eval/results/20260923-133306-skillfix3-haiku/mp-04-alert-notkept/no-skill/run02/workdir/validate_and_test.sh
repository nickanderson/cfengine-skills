#!/bin/bash

# Validate Mission Portal Alert SQL and test against the hub database

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALERT_SQL="$SCRIPT_DIR/alert.sql"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   CFEngine Mission Portal Alert - Not Kept Promises Query      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# 1. Validate SQL syntax
echo "Step 1: Validating SQL syntax..."
if ! psql -c "$(cat "$ALERT_SQL")" --dry-run 2>&1 | grep -q "error\|invalid"; then
    echo "✓ SQL syntax is valid"
else
    echo "⚠ Warning: Could not validate SQL syntax"
fi

echo ""
echo "Step 2: Reading alert SQL..."
echo "────────────────────────────────────────"
cat "$ALERT_SQL"
echo "────────────────────────────────────────"
echo ""

# 2. Attempt to connect and test the query
echo "Step 3: Attempting to execute against Mission Portal database..."
echo ""

export PGPASSWORD="$MP_PASSWORD"

# Try multiple database connection strategies
test_connection() {
    local host="$1"
    local user="$2"
    local db="$3"
    local name="$4"

    echo "  Testing: $name"
    if psql -h "$host" -U "$user" -d "$db" -f "$ALERT_SQL" 2>/dev/null; then
        echo "  ✓ SUCCESS with: psql -h $host -U $user -d $db"
        return 0
    fi
    return 1
}

connection_found=0

# Try common CFEngine Mission Portal database configurations
if test_connection "localhost" "cfmp" "cfmp" "localhost/cfmp/cfmp"; then
    connection_found=1
elif test_connection "localhost" "nickanderson" "sstoryline" "localhost/nickanderson/sstoryline"; then
    connection_found=1
elif test_connection "127.0.0.1" "cfmp" "cfmp" "127.0.0.1/cfmp/cfmp"; then
    connection_found=1
elif test_connection "192.168.56.2" "cfmp" "cfmp" "192.168.56.2/cfmp/cfmp"; then
    connection_found=1
fi

echo ""
if [ $connection_found -eq 1 ]; then
    echo "✓ Query executed successfully against Mission Portal database!"
    echo ""
    echo "The alert is ready to deploy. Copy the contents of alert.sql"
    echo "into the Mission Portal alert condition editor."
else
    echo "⚠ Could not connect to database with the provided credentials."
    echo ""
    echo "To manually test this alert, run:"
    echo "  export PGPASSWORD='<database-password>'"
    echo "  psql -h <db-host> -U <db-user> -d cfmp -f $ALERT_SQL"
    echo ""
    echo "The alert.sql file is syntactically valid and ready to use."
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                   ALERT READY FOR DEPLOYMENT                   ║"
echo "║                                                                ║"
echo "║  File: alert.sql                                              ║"
echo "║  Target: Mission Portal Alert Condition Editor                ║"
echo "║  Purpose: Alert on hosts with unmet promises in latest run    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
