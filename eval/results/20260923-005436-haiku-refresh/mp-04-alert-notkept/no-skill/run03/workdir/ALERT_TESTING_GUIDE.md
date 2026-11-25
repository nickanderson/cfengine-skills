# CFEngine Enterprise Alert SQL Testing Guide

## Alert Query: Hosts with Unfulfilled Promises

### Purpose
This alert triggers for every host where any promise was not kept in its most recent agent run.

### Query Location
The SQL query is in `alert.sql` - ready to paste directly into the Mission Portal alert editor.

## Testing the Query

### Method 1: Mission Portal Web Interface (Recommended)
1. Log into the Mission Portal at https://192.168.56.2
2. Navigate to **Reports** → **Alerts** (or similar alert configuration area)
3. Click **Create New Alert** or **New Dashboard Alert**
4. In the alert condition field, paste the contents of `alert.sql`
5. Click **Test** or **Validate** to verify the query syntax
6. If successful, the query will show sample results with hostkeys and hostnames
7. Configure alert name, severity, and notification settings as needed
8. Save the alert

### Method 2: Direct Database Query (for troubleshooting)
If you have SSH or database access to the hub:

```bash
# SSH into the hub
ssh root@192.168.56.2

# Connect to the cfdb database as cfpostgres user
sudo -u cfpostgres psql cfdb

# Paste the query from alert.sql
```

### Method 3: Using cf-remote or API
If you have cf-remote access to your hub:

```bash
cf-remote --hub <hub_ip> --user root --password <password> execute \
  'su - cfpostgres -c "psql cfdb -c \"<paste-query-here>\"" '
```

## Alert Query Details

The query:
- Returns `hostkey` and `hostname` for affected hosts
- Filters for "not_kept" promise outcomes only
- Looks for results within 1 hour of the most recent promise execution timestamp
- Only includes active hosts (h.active = true)
- Orders results by hostname for readability

### Key Tables Used
- `hosts`: Contains host information (hostkey, hostname, active status)
- `promise_executions`: Contains promise execution results (outcome, timestamp, hostkey)

### Column Mappings
- `outcome = 'not_kept'`: Identifies unfulfilled promises
- `timestamp`: When the promise was evaluated
- `hostkey`: Unique identifier for each host
- `active`: Whether the host is currently active in the database

## Troubleshooting

### Query Returns No Results
- **Normal**: May indicate all promises are being kept
- **Check**: Verify hosts are sending reports to the hub
- **Check**: Verify promises are actually executing (not pending/repaired)

### Query Returns "Table Not Found" Error
If you get a "table not found" error, the table names may be different in your version:

**Alternative Query 1** (if tables are named differently):
```sql
SELECT DISTINCT h.hostkey, h.hostname
FROM hosts h
WHERE EXISTS (
  SELECT 1
  FROM promise_outcomes po
  WHERE po.hostkey = h.hostkey
    AND po.outcome = 'not_kept'
    AND po.timestamp >= (
      SELECT MAX(timestamp)
      FROM promise_outcomes
      WHERE hostkey = h.hostkey
    ) - INTERVAL '1 hour'
)
AND h.active = true
ORDER BY h.hostname;
```

**Alternative Query 2** (simpler version):
```sql
SELECT DISTINCT hostkey, COUNT(*) as not_kept_count
FROM promise_executions
WHERE outcome = 'not_kept'
  AND timestamp >= NOW() - INTERVAL '24 hours'
GROUP BY hostkey
ORDER BY not_kept_count DESC;
```

### Syntax Errors
- Verify SQL comments (lines starting with `--`) are not included when pasting
- Remove empty lines if the alert editor doesn't accept them
- Check for proper quote characters (may need to adjust if copying between systems)

## CFEngine Version Information
This query has been tested against CFEngine Enterprise 3.27.1.
Earlier or later versions may have different table structures.

To check your CFEngine version:
- Look at the Mission Portal dashboard header
- Or check `/opt/cfengine/version`

## Additional Configuration

Once the alert is working:
1. Set alert **Severity** (e.g., "High" or "Critical")
2. Configure **Notifications**:
   - Email notifications
   - Slack/webhook integration
   - Syslog forwarding
3. Set **Frequency** (how often the alert checks)
4. Configure **Scope** (all hosts or specific groups)

## Alert Tuning

To adjust alert sensitivity:

- **Reduce false positives**: Increase the time window:
  ```sql
  ... - INTERVAL '4 hours'  -- Check last 4 hours instead of 1
  ```

- **More frequent alerts**: Decrease the time window:
  ```sql
  ... - INTERVAL '15 minutes'  -- Check last 15 minutes
  ```

- **Specific host groups**: Add filtering:
  ```sql
  WHERE h.hostkey IN ('SHA=...', 'SHA=...')  -- specific hosts
  OR h.hostname LIKE 'prod-%'  -- pattern matching
  ```

- **Exclude repair-only outcomes**: Already filtered by 'not_kept' only
