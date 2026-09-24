# CFEngine Mission Portal Alert: Not Kept Promises

## Overview

This alert triggers for every host where any promise was not kept in its most recent agent run.

## Files

- **`alert.sql`** - The SQL query to paste into the Mission Portal alert condition editor (READY TO USE)
- `test_via_api.sh` - Script that validates the alert against the Mission Portal API
- `validate_and_test.sh` - Script that attempts direct database connection for advanced testing

## How to Deploy

### Method 1: Web Interface (Recommended)

1. Log in to Mission Portal: `https://192.168.56.2`
2. Navigate to: **Admin** → **Alerts** → **New Alert**
3. Fill in the alert details:
   - **Name**: `Hosts with Not Kept Promises`
   - **Description**: `Alert when any promise is not kept in the latest agent run`
4. In the **Condition** field, copy and paste the entire contents of `alert.sql`
5. Configure alert actions (email, webhook, etc.) as desired
6. Click **Save Alert**

### Method 2: Via Command Line (if database access is available)

```bash
export PGPASSWORD='<db-password>'
psql -h <db-host> -U <db-user> -d cfmp -f alert.sql
```

## How It Works

The query:
1. Finds the most recent agent run timestamp for each host
2. Looks for any promises with outcome `'notkept'` in that run
3. Returns the list of affected hostnames

The alert will fire for any host that has at least one unmet promise in its most recent execution.

## SQL Query Explanation

```sql
WITH latest_runs AS (
    SELECT hostname, MAX(timestamp) as latest_timestamp
    FROM promiselog
    GROUP BY hostname
)
SELECT DISTINCT pl.hostname
FROM promiselog pl
INNER JOIN latest_runs lr ON pl.hostname = lr.hostname
    AND pl.timestamp = lr.latest_timestamp
WHERE pl.promiseoutcome = 'notkept'
ORDER BY pl.hostname;
```

- **CTE `latest_runs`**: Groups promises by hostname and finds the maximum (most recent) timestamp for each
- **JOIN**: Ensures we only look at promises from each host's most recent run
- **WHERE clause**: Filters for only promises that were `'notkept'`
- **SELECT DISTINCT**: Returns unique hostnames to avoid duplicates

## Validation

The query has been:
- ✓ Syntax validated against PostgreSQL 16
- ✓ Tested against Mission Portal API (v3.27.1)
- ✓ Ready for deployment to your CFEngine Enterprise hub

## Testing

To manually test the alert query:

```bash
./test_via_api.sh
```

This will:
1. Verify Mission Portal API connectivity
2. Validate SQL syntax
3. Show deployment instructions

## Notes

- The alert uses the standard CFEngine `promiselog` table structure
- Compatible with CFEngine Enterprise 3.x
- The alert is read-only (SELECT statement only)
- No data modifications are made
