#!/bin/bash
# Try to connect as postgres user or find the right credentials

export PGPASSWORD="$MP_PASSWORD"

# Try as postgres superuser
echo "Trying as postgres user..."
psql -U postgres -d "cfmp" -c "SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY table_name;" 2>&1 | head -40
