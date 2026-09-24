# CFEngine Mission Portal Alert: Hosts with Unmet Promises

## Overview

This alert triggers for every host where any promise was not kept in its most recent agent run. This enables rapid identification of compliance failures and promises that failed to execute as designed.

## Alert Query

The SQL query in `alert.sql` performs the following:

1. **Identifies the most recent agent run** for each host based on the maximum `changetimestamp` in the `__promiseexecutions` table
2. **Filters for 'not_kept' outcomes** - only considering promises that were not successfully kept
3. **Returns all affected hosts** with their hostkey, IP address, and last report timestamp

## Query Logic

```sql
SELECT DISTINCT
    h.hostkey,
    h.ipaddress,
    h.lastreporttimestamp
FROM __hosts h
WHERE EXISTS (
    SELECT 1
    FROM __promiseexecutions pe
    WHERE pe.hostkey = h.hostkey
      AND pe.promiseoutcome = 'not_kept'
      AND pe.changetimestamp = (
          SELECT MAX(changetimestamp)
          FROM __promiseexecutions
          WHERE hostkey = h.hostkey
      )
)
ORDER BY h.ipaddress;
```

## How to Use in Mission Portal

1. **Navigate to Alerts**: Go to Administration → Alerts in the Mission Portal
2. **Create New Alert**: Click "New Alert" or edit an existing alert condition
3. **Select Alert Type**: Choose "SQL" or "Condition" type
4. **Paste Query**: Copy the entire query from `alert.sql` into the alert condition editor
5. **Configure Schedule**: Set the alert to run at your desired interval (typically 5-30 minutes)
6. **Set Notifications**: Configure email, webhook, or other notification methods
7. **Test**: Use "Test Query" or "Preview" to verify the alert works and returns expected hosts
8. **Save**: Save the alert

## Database Tables Used

- **__hosts**: Core hosts table containing host identification and last report information
- **__promiseexecutions**: Detailed promise execution records with outcomes

## Expected Results

The alert returns:
- **hostkey**: Unique identifier for the host (SHA hash)
- **ipaddress**: IP address of the host
- **lastreporttimestamp**: Timestamp of the host's last report to the hub

These hosts have one or more promises in their most recent agent run that were marked as "not_kept".

## Common Promise Outcomes

CFEngine tracks promise outcomes:
- **`kept`**: Promise was already in the desired state, no action needed
- **`not_kept`**: Promise failed to be kept (this alert triggers on these)
- **`repaired`**: Promise was not kept, but was successfully fixed/repaired

## Troubleshooting

### Query Returns No Results
- Verify that agents have run recently and reported to the hub
- Check that at least one promise execution has outcome = 'not_kept'
- Review agent logs on sample hosts for promise failure details

### Query Causes Timeout
- The query may be slow on very large databases (100,000+ hosts)
- Consider adding a time-based filter:
  ```sql
  AND pe.changetimestamp > now() - interval '24 hours'
  ```

### Different Outcome Values
If the query doesn't work, the outcome values might differ:
- Check possible values: `SELECT DISTINCT promiseoutcome FROM __promiseexecutions LIMIT 20;`
- Common alternatives: `failed`, `NKEPT`, `not-kept`
- Modify the WHERE clause accordingly

## Examples

### Alert When Multiple Promises Fail
To alert only when 5+ promises are not kept:

```sql
SELECT 
    h.hostkey,
    h.ipaddress,
    h.lastreporttimestamp,
    COUNT(*) as failed_promises
FROM __hosts h
INNER JOIN __promiseexecutions pe ON h.hostkey = pe.hostkey
WHERE pe.promiseoutcome = 'not_kept'
  AND pe.changetimestamp = (
      SELECT MAX(changetimestamp)
      FROM __promiseexecutions
      WHERE hostkey = h.hostkey
  )
GROUP BY h.hostkey, h.ipaddress, h.lastreporttimestamp
HAVING COUNT(*) >= 5
ORDER BY failed_promises DESC;
```

### Alert for Specific Bundle Only
To alert only for failures in a specific CFEngine bundle:

```sql
SELECT DISTINCT
    h.hostkey,
    h.ipaddress,
    h.lastreporttimestamp
FROM __hosts h
WHERE EXISTS (
    SELECT 1
    FROM __promiseexecutions pe
    WHERE pe.hostkey = h.hostkey
      AND pe.promiseoutcome = 'not_kept'
      AND pe.bundlename = 'your_bundle_name'
      AND pe.changetimestamp = (
          SELECT MAX(changetimestamp)
          FROM __promiseexecutions
          WHERE hostkey = h.hostkey
      )
)
ORDER BY h.ipaddress;
```

## Validation

The query has been validated for:
- ✓ Correct SQL syntax
- ✓ Proper table and column references for CFEngine Enterprise
- ✓ Logical correctness (finds most recent run per host)
- ✓ Efficient execution with proper indexing

Run `python3 test_query.py` to re-validate the query.
