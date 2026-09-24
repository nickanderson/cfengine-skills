#!/bin/bash
# Try different approaches to connect to the database

# First check if we're on the hub itself
if [ -f /var/cfengine/cfapache/config.sh ]; then
  echo "On CFEngine hub, sourcing config..."
  source /var/cfengine/cfapache/config.sh
  echo "DB Variables found"
fi

# Try common PostgreSQL socket connections
export PGPASSWORD="$MP_PASSWORD"

# Try socket connection without host
echo "Trying socket connection..."
psql -U "$MP_USER" -d "cfmp" -c "SELECT version();" 2>&1

# Or try localhost
echo "Trying localhost connection..."
psql -h localhost -U "$MP_USER" -d "cfmp" -c "SELECT version();" 2>&1

# Also try the raw URL host
echo "Trying via TCP..."
psql -h 192.168.56.2 -p 5432 -U "$MP_USER" -d "cfmp" -c "SELECT version();" 2>&1
