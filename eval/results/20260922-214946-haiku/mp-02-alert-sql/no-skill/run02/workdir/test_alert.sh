#!/bin/bash

# Test the alert SQL against the Mission Portal database

# Check environment variables
if [ -z "$MP_URL" ] || [ -z "$MP_USER" ] || [ -z "$MP_PASSWORD" ]; then
    echo "Error: Missing required environment variables (MP_URL, MP_USER, MP_PASSWORD)"
    exit 1
fi

# Extract database host from MP_URL (remove https:// and port)
# Format typically: https://hub.example.com:8080
DB_HOST=$(echo "$MP_URL" | sed -E 's|https?://([^:/]+).*|\1|')
DB_PORT="${MP_DB_PORT:-5432}"
DB_NAME="${MP_DB_NAME:-cfengine}"
DB_USER="${MP_USER}"
DB_PASSWORD="${MP_PASSWORD}"

echo "Testing Mission Portal alert SQL..."
echo "Database Host: $DB_HOST"
echo "Database Port: $DB_PORT"
echo "Database Name: $DB_NAME"
echo "Database User: $DB_USER"
echo ""

# Read the SQL query
SQL_QUERY=$(cat /tmp/cfeval-mp-02-alert-sql-no-skill.GZClgR8V/work/alert.sql)

# Test connection and execute query
PGPASSWORD="$DB_PASSWORD" psql \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    -d "$DB_NAME" \
    -U "$DB_USER" \
    -c "$SQL_QUERY" \
    2>&1

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Query executed successfully against the Mission Portal database"
else
    echo ""
    echo "✗ Query execution failed - checking if database is accessible"
    # Try to get basic connection info
    PGPASSWORD="$DB_PASSWORD" psql \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -d "$DB_NAME" \
        -U "$DB_USER" \
        -c "SELECT version();" 2>&1 | head -20
fi
