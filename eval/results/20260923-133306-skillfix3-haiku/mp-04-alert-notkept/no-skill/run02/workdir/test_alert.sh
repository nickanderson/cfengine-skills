#!/bin/bash
set -e

# Mission Portal database connection
MP_HOST="${MP_URL#*://}"  # Extract host from URL
MP_HOST="${MP_HOST%%/*}"   # Remove any path
MP_PORT="${MP_PORT:-5432}"
MP_DB="${MP_DB:-cfmp}"

# For testing with psql, we need the database credentials
echo "Testing connection to Mission Portal database..."

# Test 1: Explore the schema to understand the table structure
echo ""
echo "=== Step 1: Exploring database schema ==="
PGPASSWORD="$MP_PASSWORD" psql -h "$MP_HOST" -U "$MP_USER" -d "$MP_DB" -c "\dt" 2>/dev/null || {
    echo "Could not connect to database. Checking alternative connection methods..."
}

# Step 2: Query for tables related to promises and hosts
echo ""
echo "=== Step 2: Looking for promise-related tables ==="
PGPASSWORD="$MP_PASSWORD" psql -h "$MP_HOST" -U "$MP_USER" -d "$MP_DB" -c "
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
AND table_name ILIKE '%promise%' OR table_name ILIKE '%log%'
ORDER BY table_name;" 2>/dev/null || true

# Step 3: Check hosts table structure
echo ""
echo "=== Step 3: Checking hosts table ==="
PGPASSWORD="$MP_PASSWORD" psql -h "$MP_HOST" -U "$MP_USER" -d "$MP_DB" -c "\d hosts" 2>/dev/null || true

# Step 4: Query the most recent promise data
echo ""
echo "=== Step 4: Sample data from promise tables ==="
PGPASSWORD="$MP_PASSWORD" psql -h "$MP_HOST" -U "$MP_USER" -d "$MP_DB" -c "
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name='promiselog'
ORDER BY ordinal_position LIMIT 20;" 2>/dev/null || true
