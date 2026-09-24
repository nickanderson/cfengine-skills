#!/bin/bash
set -e

# Extract hostname from URL
HUB_HOST=$(echo "$MP_URL" | sed 's|https://||' | sed 's|/.*||')

echo "Testing alert SQL against CFEngine hub at: $HUB_HOST"
echo "================================"

# Try to connect to PostgreSQL database
# CFEngine typically uses cfdb database with default password
psql -h "$HUB_HOST" -U "$MP_USER" -d cfdb -w -c "
SELECT h.hostkey
FROM hosts h
WHERE h.hostname IN (
    SELECT hostname
    FROM hosts
    GROUP BY hostname
    HAVING COUNT(DISTINCT hostkey) > 1
)
ORDER BY h.hostname, h.hostkey;" 2>&1

echo "✓ Alert SQL executed successfully"
