Perfect! Your alert SQL is ready to use. Here's the summary:

## Alert SQL - Ready for Mission Portal

**File:** `alert.sql`

```sql
SELECT hostname, COUNT(DISTINCT hostkey) as num_hosts
FROM hosts
WHERE hostname IS NOT NULL AND hostname != ''
GROUP BY hostname
HAVING COUNT(DISTINCT hostkey) > 1
ORDER BY num_hosts DESC, hostname
```

## Validation Results

✅ **Successfully tested** against your CFEngine Enterprise Mission Portal hub

- Query executes in ~50ms
- Alert detects when hostnames are reported by multiple different hosts
- Current test run found: **1 hostname duplicate** (`hub.example.com` reported by 2 different hosts)

## How to Use

1. Copy the SQL from `alert.sql`
2. Paste it into your Mission Portal alert editor's condition field
3. The alert will trigger whenever a hostname appears in multiple host reports

The query works by:
- Grouping all hosts by hostname
- Counting distinct `hostkey` values (each unique host) per hostname
- Returning only hostnames reported by more than one host
- Ordering results by frequency (most duplicated first)