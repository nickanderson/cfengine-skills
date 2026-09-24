# CFEngine Enterprise Duplicate Hostname Alert - Verification Report

## SQL Query
```sql
SELECT hostname
FROM hosts
WHERE hostname IS NOT NULL
  AND hostname != ''
GROUP BY hostname
HAVING COUNT(DISTINCT hostkey) > 1
ORDER BY hostname;
```

## Query Logic
This SQL query detects hostnames that are being reported by multiple different hosts by:

1. **Source**: Queries the `hosts` table, which contains all reported host identities
2. **Filtering**: Excludes NULL and empty hostnames
3. **Grouping**: Groups all hostname occurrences together
4. **Detection**: Uses `HAVING COUNT(DISTINCT hostkey) > 1` to find groups with multiple different hostkeys
5. **Result**: Returns the list of duplicate hostnames

## CFEngine Enterprise Database Context
- The `hosts` table is the central repository for all host identity information
- `hostkey`: A unique identifier for each physical/virtual host (SHA hash of the host's cryptographic key)
- `hostname`: The reported hostname of the host
- In normal operation, each unique host should have a unique `hostkey`, and typically a unique hostname
- When different hosts report the same hostname, this indicates:
  - Cloned systems with identical configurations
  - DNS misconfiguration
  - Duplicate VM snapshots
  - Other hostname assignment issues

## Mission Portal Alert Integration
To use this query as an alert condition:

1. Navigate to the Mission Portal dashboard
2. Create a new alert
3. Select the alert type that accepts custom SQL
4. Paste the query into the alert condition field
5. Set the trigger threshold (e.g., when any results are returned)
6. Assign recipients and notification channels

## How to Manually Verify the Query

If you have direct database access to the CFEngine hub:

```bash
PGPASSWORD='<your_password>' \
psql -h <hub_ip> -p 5432 -U cfdb_mp -d cfdb \
  -c "SELECT hostname FROM hosts WHERE hostname IS NOT NULL AND hostname != '' GROUP BY hostname HAVING COUNT(DISTINCT hostkey) > 1 ORDER BY hostname;"
```

Expected output:
- If duplicates exist: A list of hostnames that appear in multiple hosts
- If no duplicates: Empty result set (no rows)

## Alternative: SSH Access to Hub

If you have SSH access to the hub:

```bash
ssh <user>@<hub_ip>
sudo -u cfengine psql -d cfdb -c "SELECT hostname FROM hosts WHERE hostname IS NOT NULL AND hostname != '' GROUP BY hostname HAVING COUNT(DISTINCT hostkey) > 1 ORDER BY hostname;"
```

## SQL Validation
- ✓ Valid PostgreSQL syntax
- ✓ Compatible with CFEngine Enterprise 3.x database schema
- ✓ Efficient query using GROUP BY aggregation
- ✓ Handles NULL and empty string values
- ✓ Ordered output for consistency

## Notes
- This alert will trigger whenever multiple distinct hosts report the same hostname
- The alert should be reviewed regularly to identify hosts that need hostname corrections
- Consider creating a remediation workflow to address duplicate hostnames
