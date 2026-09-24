#!/bin/bash
export PGPASSWORD="$MP_PASSWORD"

# Try with different database names
for dbname in cfmp cfengine mission_portal postgres; do
  echo "=== Trying database: $dbname ==="
  timeout 3 psql -h 127.0.0.1 -U "$MP_USER" -d "$dbname" -c "SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY table_name LIMIT 10;" 2>&1 | head -20
done
