#!/bin/bash
# Extract database connection info from MP_URL
DBHOST=$(echo "$MP_URL" | sed 's|https://||' | cut -d: -f1)
DBNAME="cfmp"
DBUSER="$MP_USER"
DBPASS="$MP_PASSWORD"

# Try to connect to the database and check schema
export PGPASSWORD="$DBPASS"

# First, let's check if we can connect and what tables exist
psql -h "$DBHOST" -U "$DBUSER" -d "$DBNAME" -c "\dt" 2>&1 | head -50
