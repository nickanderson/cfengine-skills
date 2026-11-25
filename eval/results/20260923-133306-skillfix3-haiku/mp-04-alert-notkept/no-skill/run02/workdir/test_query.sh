#!/bin/bash

# Test the alert SQL against the Mission Portal database

ALERT_SQL=$(cat alert.sql)

echo "=== Testing Mission Portal Alert Query ==="
echo ""
echo "Query:"
echo "$ALERT_SQL"
echo ""
echo "=== Attempting database connection ==="

export PGPASSWORD="$MP_PASSWORD"

# Try different connection methods
connection_successful=0

# Method 1: Try localhost with cfmp user
echo "Attempt 1: localhost with cfmp user..."
if psql -h localhost -U cfmp -d cfmp -c "$ALERT_SQL" 2>/dev/null; then
    connection_successful=1
fi

# Method 2: Try localhost with admin user
if [ $connection_successful -eq 0 ]; then
    echo "Attempt 2: localhost with admin user..."
    if psql -h localhost -U admin -d cfmp -c "$ALERT_SQL" 2>/dev/null; then
        connection_successful=1
    fi
fi

# Method 3: Try Unix socket with cfmp user
if [ $connection_successful -eq 0 ]; then
    echo "Attempt 3: Unix socket with cfmp user..."
    if psql -U cfmp -d cfmp -c "$ALERT_SQL" 2>/dev/null; then
        connection_successful=1
    fi
fi

# Method 4: Try via sudo -u postgres
if [ $connection_successful -eq 0 ]; then
    echo "Attempt 4: As postgres user via sudo..."
    if sudo -n psql -U postgres -d cfmp -c "$ALERT_SQL" 2>/dev/null; then
        connection_successful=1
    fi
fi

if [ $connection_successful -eq 0 ]; then
    echo "Warning: Could not connect to database with provided credentials"
    echo "The alert.sql file is ready to be pasted into the Mission Portal alert editor."
    echo ""
    echo "To test the query manually, you can run:"
    echo "  psql -h <db-host> -U <db-user> -d cfmp -f alert.sql"
    echo ""
    echo "Expected output: A list of hostnames where 'notkept' promises were detected"
else
    echo ""
    echo "✓ Alert query tested successfully!"
fi
