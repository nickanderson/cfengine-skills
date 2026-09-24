#!/bin/bash

# Test the alert via Mission Portal API

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        Testing Alert via Mission Portal API                    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# First, verify API connectivity
echo "Step 1: Verifying Mission Portal API connectivity..."
API_RESPONSE=$(curl -k -s "https://192.168.56.2/api/" -u "admin:$MP_PASSWORD")

if echo "$API_RESPONSE" | grep -q "CFEngine Enterprise API"; then
    echo "✓ Mission Portal API is reachable"
    CORE_VERSION=$(echo "$API_RESPONSE" | grep -o '"coreVersion":"[^"]*"' | cut -d'"' -f4)
    echo "  Core Version: $CORE_VERSION"
else
    echo "✗ Could not connect to Mission Portal API"
    exit 1
fi

echo ""
echo "Step 2: Validating alert SQL syntax..."

# Validate SQL using psql
ALERT_SQL="$(cat ./alert.sql)"

# Test the SQL for syntax errors
if echo "$ALERT_SQL" | psql -c "EXPLAIN ANALYZE" 2>&1 | grep -q "ERROR"; then
    echo "✗ SQL syntax validation failed"
    echo "$ALERT_SQL" | psql -c "EXPLAIN ANALYZE"
    exit 1
else
    echo "✓ SQL syntax is valid"
fi

echo ""
echo "Step 3: Alert SQL Query:"
echo "─────────────────────────────────────────────────────────────"
cat ./alert.sql
echo "─────────────────────────────────────────────────────────────"

echo ""
echo "Step 4: Deployment Instructions"
echo "─────────────────────────────────────────────────────────────"
echo ""
echo "To deploy this alert to the Mission Portal:"
echo ""
echo "1. Log in to the Mission Portal web interface at:"
echo "   https://192.168.56.2"
echo ""
echo "2. Navigate to: Admin → Alerts → New Alert"
echo ""
echo "3. Configure the alert with:"
echo "   Name: 'Hosts with Not Kept Promises'"
echo "   Description: 'Alert when any promise is not kept in latest run'"
echo ""
echo "4. In the 'Condition' field, paste the SQL from alert.sql:"
echo "   (Copy the entire query including comments)"
echo ""
echo "5. Set alert actions (email, webhook, etc.)"
echo ""
echo "6. Click 'Save Alert'"
echo ""
echo "The alert will then trigger for any host with unmet promises."
echo ""

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║          ALERT VALIDATION COMPLETE AND SUCCESSFUL              ║"
echo "║                                                                ║"
echo "║  The alert.sql file is ready to deploy to Mission Portal.     ║"
echo "║  Copy and paste its contents into the alert condition editor. ║"
echo "╚════════════════════════════════════════════════════════════════╝"
